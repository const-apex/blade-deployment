#!/bin/bash -x

main() {
    mkdir /var/lib/bootstrap /var/lib/bootstrap/secrets
    pushd /var/lib/bootstrap

    {% for item in hostvars %}
        {% if (hostvars[item].tags.Role == "fullnode" or hostvars[item].tags.Role == "validator") %}
            sed 's/host/{{hostvars[item].tags["Name"]}}/g' {{ blade_home_dir }}/config.json > secrets/{{ hostvars[item].tags["Name"] }}_config.json
            blade secrets init --config secrets/{{ hostvars[item].tags["Name"] }}_config.json --json > {{ hostvars[item].tags["Name"] }}.json
        {% endif %}
    {% endfor %}

    ZERO_ADDRESS=0x0000000000000000000000000000000000000000
    PROXY_CONTRACTS_ADMIN=0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed

    AMT_24=1000000000000000000000000

    blade genesis \
        --consensus polybft \
        --chain-id {{ chain_id }} \
        {% for item in hostvars %}{% if (hostvars[item].tags.Role == "validator") %} --validators /dns4/{{ hostvars[item].tags["Name"] }}/tcp/{{ blade_p2p_port }}/p2p/$(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].node_id'):$(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].address' | sed 's/^0x//'):$(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].bls_pubkey') {% endif %}{% endfor %} \
        {% for item in hostvars %}{% if (hostvars[item].tags.Role == "fullnode") %} --premine $(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].address'):$AMT_24 {% endif %}{% endfor %} \
        --block-gas-limit {{ block_gas_limit }} \
        --premine {{ loadtest_account }}:$AMT_24 \
        --premine $ZERO_ADDRESS \
        {% if (is_london_fork_active) %} --burn-contract 0:$ZERO_ADDRESS \ {% endif %}
        --epoch-size 10 \
        --reward-wallet 0xDEADBEEF:1000000 \
        --block-time {{ block_time }}s \
        --native-token-config {{ native_token_config }} \
        --blade-admin $(cat validator-001.{{ base_dn }}.json | jq -r '.[0].address') \
        --proxy-contracts-admin $PROXY_CONTRACTS_ADMIN \
        --base-fee-config 1000000000

    {% if (is_bridge_active) %}
        blade bridge server 2>&1 | tee bridge-server.log &
        
        blade bridge fund \
            --addresses $(cat validator-*.json fullnode-*.json | jq -r ".[0].address" | paste -sd ',' - | tr -d '\n') \
            --amounts $(paste -sd ',' <(yes "1000000000000000000000000" | head -n `ls validator-*.json fullnode-*.json | wc -l`) | tr -d '\n')

        blade bridge deploy \
            --proxy-contracts-admin $PROXY_CONTRACTS_ADMIN \
            --test
    {% endif %}

    tar czf {{ base_dn }}.tar.gz *.json secrets/
    popd
}

main