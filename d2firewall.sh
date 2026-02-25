#!/bin/bash

# --- CONFIGURAÇÃO ---
PROJETO_DIR="/home/ubuntu/meu-projeto"

# --- FUNÇÃO START ---
start() {
    echo "Iniciando monitoramento em tempo real (1s)..."
    echo "Pressione CTRL+C para sair."
    
    cd "$PROJETO_DIR" || exit 1

    # Executa o Node.js
    node -e '
const { ethers } = require("ethers");

async function run() {
    [cite_start]// RPCs alternativas para evitar quedas [cite: 1]
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    console.log("Monitor ativo. Aguardando dados...");

    // Intervalo de 1 segundo (1000ms)
    setInterval(async () => {
        try {
            const roundData = await priceFeed.latestRoundData();
            const price = Number(roundData[1]) / 1e8;
            const now = new Date().toLocaleTimeString();
            
            // Limpa a linha atual e escreve o novo preço
            process.stdout.write(`\r[${now}] BTC/USD: $${price.toFixed(2)} `);
        } catch (err) {
            process.stdout.write(`\r[Erro] Falha ao ler dados. Tentando novamente... `);
        }
    }, 1000);
}

run();
'
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Parando monitoramento..."
    # Mata qualquer processo node iniciado por este script
    pkill -f "node" 2>/dev/null
    echo "Status: Parado."
}

# --- CONTROLE ---
case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}"; exit 1 ;;
esac
