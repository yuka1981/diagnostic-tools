# Reactor: forward benchmark job returns to Rails webhook
# This reactor fires when any job completes on a minion
{% if 'benchmark' in data.get('fun', '') or 'state.apply' in data.get('fun', '') %}
notify_rails:
  runner.http.query:
    - url: {{ salt['config.get']('rails_webhook_url', 'http://localhost:3000/api/v1/salt/events') }}
    - method: POST
    - header_dict:
        Content-Type: application/json
        Authorization: "Bearer {{ salt['config.get']('rails_api_token', '') }}"
    - data: {{ {"tag": tag, "fun": data['fun'], "id": data['id'], "jid": data['jid'], "retcode": data.get('retcode', -1), "return": data.get('return', {})} | tojson }}
{% endif %}
