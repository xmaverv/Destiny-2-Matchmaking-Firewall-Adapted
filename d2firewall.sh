#!/bin/bash

# --- CONFIGURAÇÃO ---
PROJETO_DIR="/home/ubuntu/meu-projeto"

# --- FUNÇÃO START ---
start() {
    echo "Iniciando monitoramento contínuo (1s)... Pressione CTRL+C para parar."
    
    cd "$PROJETO_DIR" || exit 1

    # Executa o Node.js em modo de loop infinito
    node -e '
const { ethers } = require("ethers");

async function monitor() {
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    console.clear();
    console.log("=== MONITORAMENTO CHAINLINK BTC/USD ===");

    while (true) {
        try {
            const roundData = await priceFeed.latestRoundData();
            const price = Number(roundData[1]) / 1e8;
            const timestamp = new Date().toLocaleTimeString();
            
            // Move o cursor para cima para atualizar o preço no mesmo lugar
            process.stdout.write(`\rHora: ${timestamp} | Preço: $${price.toFixed(2)}      `);
            
        } catch (error) {
            process.stdout.write(`\rErro na conexão: Tentando reconectar...      `);
        }
        // Aguarda 1000ms (1 segundo) antes da próxima consulta
        await new Promise(resolve => setTimeout(resolve, 1000));
    }
}
monitor();
'
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Interrompendo monitoramento..."
    # Encerra o processo do Node
    pkill -f "node" 2>/dev/null
    echo "Status: Monitoramento Finalizado."
}

# --- CONTROLE ---
case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}"; exit 1 ;;
esac
