#!/bin/bash

# --- CONFIGURAÇÃO ---
PROJETO_DIR="/home/ubuntu/meu-projeto"

# --- FUNÇÃO START ---
start() {
    echo "Iniciando monitoramento em tempo real (1s)..."
    echo "Pressione CTRL+C para sair."
    
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");

async function run() {
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    setInterval(async () => {
        try {
            const roundData = await priceFeed.latestRoundData();
            const price = Number(roundData[1]) / 1e8;
            const now = new Date().toLocaleTimeString();
            process.stdout.write(`\r[${now}] BTC/USD: $${price.toFixed(2)} `);
        } catch (err) {
            process.stdout.write(`\r[${new Date().toLocaleTimeString()}] Erro de conexao... `);
        }
    }, 1000);
}
run();
'
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Parando monitoramento..."
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
