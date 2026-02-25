#!/bin/bash

# --- CONFIGURAÇÃO ---
# Definindo o caminho onde o ethers está instalado
PROJETO_DIR="/home/ubuntu/meu-projeto"

# --- FUNÇÃO START ---
start() {
    echo "Conectando ao RPC da Polygon..."
    
    # Entra na pasta onde os módulos existem
    cd "$PROJETO_DIR" || exit 1

    # Executa o Node.js com o código limpo
    node -e '
const { ethers } = require("ethers");

async function getBtcPrice() {
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    try {
        const roundData = await priceFeed.latestRoundData();
        const price = Number(roundData[1]) / 1e8;
        console.log("------------------------------------------");
        console.log("Preço BTC/USD (Chainlink): $" + price);
        console.log("------------------------------------------");
    } catch (error) {
        console.error("Erro na consulta:", error.message);
    }
}
getBtcPrice();
'
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Limpando processos..."
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
