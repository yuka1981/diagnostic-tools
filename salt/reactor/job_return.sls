# Reactor: forward benchmark job returns to Rails webhook
# This reactor fires when any job completes on a minion
{% set fun = data.get('fun', '') %}
{% set fun_args_str = data.get('fun_args', [])|string %}
{% if 'benchmark' in fun or (fun == 'state.apply' and 'benchmark' in fun_args_str) %}
notify_rails:
  runner.http.query:
    - url: {{ salt['config.get']('rails_webhook_url', 'http://localhost:3000/api/v1/salt/events') }}
    - method: POST
    - header_dict:
        Content-Type: application/json
        Authorization: "Bearer {{ salt['config.get']('rails_api_token', '') }}"
    - data: {{ {"tag": tag, "fun": data.get('fun', ''), "id": data.get('id', ''), "jid": data.get('jid', ''), "retcode": data.get('retcode', -1), "return": data.get('return', {})} | tojson }}
{% endif %}
