# Reactor: notify Rails when minion presence changes
notify_rails_presence:
  runner.http.query:
    - url: {{ salt['config.get']('rails_webhook_url', 'http://localhost:3000/api/v1/salt/events') }}
    - method: POST
    - header_dict:
        Content-Type: application/json
        Authorization: "Bearer {{ salt['config.get']('rails_api_token', '') }}"
    - data: {{ {"tag": "salt/presence/change", "new": data.get('new', []), "lost": data.get('lost', [])} | tojson }}
