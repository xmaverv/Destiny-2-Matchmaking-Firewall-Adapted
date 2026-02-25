#!/bin/bash

# --- FUNÇÃO START ---
start() {
    echo "Conectando ao RPC da Polygon..."
    
    # Define o caminho para localizar o modulo ethers na sua pasta atual
    export NODE_PATH=$(pwd)/node_modules

    node -e '
const { ethers } = require("ethers");

async function getBtcPrice() {
    const rpcUrls = [
        "https://polygon-bor-rpc.publicnode.com",
        "https://1rpc.io/matic",
        "https://polygon.llamarpc.com"
    ];

    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const aggregatorV3InterfaceABI = [
        "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)"
    ];

    for (const url of rpcUrls) {
        try {
            const provider = new ethers.JsonRpcProvider(url);
            const priceFeed = new ethers.Contract(btcUsdAddress, aggregatorV3InterfaceABI, provider);
            const roundData = await priceFeed.latestRoundData();
            const price = Number(roundData.answer) / 10**8;
            
            console.log("------------------------------------------");
            console.log("Preço Oficial Chainlink (BTC/USD): $" + price);
            console.log("------------------------------------------");
            return;
        } catch (error) {
            continue;
        }
    }
    console.error("Erro: Nao foi possivel conectar as RPCs.");
}

getBtcPrice();
'
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Encerrando processo..."
    pkill -f "node" 2>/dev/null
    echo "Status: Parado."
}

# --- CONTROLE DE EXECUÇÃO ---
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Uso: $0 {start|stop|restart}"
        exit 1
esac
