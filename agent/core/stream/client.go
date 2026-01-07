package stream

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

const (
	// DefaultChannel is the ActionCable channel name
	DefaultChannel = "AgentChannel"
	// RetryWaitMin is the minimum wait time for reconnection
	RetryWaitMin = 1 * time.Second
	// RetryWaitMax is the maximum wait time for reconnection
	RetryWaitMax = 30 * time.Second
)

// CommandHandler handles commands received from the server
type CommandHandler interface {
	HandleCommand(ctx context.Context, action string, payload map[string]interface{}, responder Responder) error
}

// Responder allows the handler to send responses back to the server
type Responder interface {
	Send(ctx context.Context, payload interface{}) error
}

// Client manages the WebSocket connection to the server
type Client struct {
	serverURL string
	token     string
	nodeID    string

	// Reordered for alignment
	conn    *websocket.Conn
	handler CommandHandler
	writeMu sync.Mutex
}

// NewClient creates a new WebSocket client
func NewClient(serverURL, token, nodeID string, handler CommandHandler) *Client {
	return &Client{
		serverURL: serverURL,
		token:     token,
		nodeID:    nodeID,
		handler:   handler,
	}
}

// Start begins the connection loop. It blocks until the context is canceled.
func (c *Client) Start(ctx context.Context) error {
	attempt := 0
	for {
		select {
		case <-ctx.Done():
			return nil
		default:
		}

		log.Printf("Attempting connection (attempt %d)...", attempt+1)
		err := c.connectAndListen(ctx)
		if err != nil {
			log.Printf("WebSocket connection error: %v", err)
		}

		// Reconnect with backoff
		attempt++
		wait := time.Duration(math.Pow(2, float64(attempt))) * RetryWaitMin
		if wait > RetryWaitMax {
			wait = RetryWaitMax
		}

		log.Printf("Reconnecting in %v...", wait)
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(wait):
		}
	}
}

func (c *Client) connectAndListen(ctx context.Context) error {
	conn, err := c.dial(ctx)
	if err != nil {
		return err
	}

	c.writeMu.Lock()
	c.conn = conn
	c.writeMu.Unlock()

	defer func() {
		conn.Close(websocket.StatusInternalError, "connection closed")

		c.writeMu.Lock()
		defer c.writeMu.Unlock()
		if c.conn == conn {
			c.conn = nil
		}
	}()

	if err := c.subscribe(ctx, conn); err != nil {
		return err
	}

	return c.readLoop(ctx, conn)
}

func (c *Client) dial(ctx context.Context) (*websocket.Conn, error) {
	wsURL := c.prepareURL()

	opts := &websocket.DialOptions{
		HTTPHeader: http.Header{
			"X-Node-ID": []string{c.nodeID},
		},
	}
	if c.token != "" {
		opts.HTTPHeader.Set("Authorization", "Bearer "+c.token)
	}

	log.Printf("Connecting to %s...", wsURL)
	conn, resp, err := websocket.Dial(ctx, wsURL, opts)
	if resp != nil && resp.Body != nil {
		resp.Body.Close()
	}
	if err != nil {
		return nil, fmt.Errorf("dial failed: %w", err)
	}
	return conn, nil
}

func (c *Client) subscribe(ctx context.Context, conn *websocket.Conn) error {
	identifier := fmt.Sprintf(`{"channel":%q}`, DefaultChannel)
	subscribeMsg := map[string]interface{}{
		"command":    "subscribe",
		"identifier": identifier,
	}

	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if err := wsjson.Write(ctx, conn, subscribeMsg); err != nil {
		return fmt.Errorf("subscribe failed: %w", err)
	}
	return nil
}

func (c *Client) readLoop(ctx context.Context, conn *websocket.Conn) error {
	for {
		var msg map[string]interface{}
		if err := wsjson.Read(ctx, conn, &msg); err != nil {
			return fmt.Errorf("read failed: %w", err)
		}

		c.handleMessage(ctx, msg)
	}
}

func (c *Client) handleMessage(ctx context.Context, msg map[string]interface{}) {
	msgType, _ := msg["type"].(string)
	if msgType == "ping" || msgType == "welcome" {
		return
	}

	if msgType == "confirm_subscription" {
		log.Println("Subscribed to AgentChannel")
		return
	}

	if message, ok := msg["message"].(map[string]interface{}); ok {
		action, _ := message["action"].(string)
		if c.handler != nil && action != "" {
			go func(a string, p map[string]interface{}) {
				if err := c.handler.HandleCommand(ctx, a, p, c); err != nil {
					log.Printf("Command %s execution failed: %v", a, err)
				}
			}(action, message)
		}
	}
}

// Send implements Responder
func (c *Client) Send(ctx context.Context, payload interface{}) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if c.conn == nil {
		return fmt.Errorf("connection not established")
	}

	// ActionCable expects "command": "message", "identifier": ..., "data": JSON_STRING
	identifier := fmt.Sprintf(`{"channel":%q}`, DefaultChannel)

	dataBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload failed: %w", err)
	}

	msg := map[string]interface{}{
		"command":    "message",
		"identifier": identifier,
		"data":       string(dataBytes),
	}

	return wsjson.Write(ctx, c.conn, msg)
}

func (c *Client) prepareURL() string {
	u, err := url.Parse(c.serverURL)
	if err != nil || u.Scheme == "" || u.Host == "" {
		// Fallback for simple hostnames like "localhost:3000"
		u, _ = url.Parse("http://" + c.serverURL)
	}

	if u.Scheme == "https" {
		u.Scheme = "wss"
	} else {
		u.Scheme = "ws"
	}

	u.Path = "/cable"
	return u.String()
}
