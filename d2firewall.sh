#!/bin/bash

# --- CONFIGURAÇÃO ---
PROJETO_DIR="/home/ubuntu/meu-projeto"

# --- FUNÇÃO START ---
start() {
    echo "Iniciando Monitor Híbrido: Binance (Order Book) + Chainlink..."
    echo "Pressione CTRL+C para sair."
    
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");

async function run() {
    // Configuração Chainlink (Polygon)
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let binancePrice = 0;
    let chainlinkPrice = 0;

    // 1. Conexão WebSocket Binance (Preço do Order Book em tempo real)
    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@bookTicker");

    ws.on("message", (data) => {
        const msg = JSON.parse(data);
        // Calcula o preço médio entre a melhor oferta de compra (bid) e venda (ask)
        binancePrice = (parseFloat(msg.b) + parseFloat(msg.a)) / 2;
    });

    // 2. Loop de atualização a cada 1 segundo
    setInterval(async () => {
        try {
            // Consulta Chainlink
            const roundData = await priceFeed.latestRoundData();
            chainlinkPrice = Number(roundData[1]) / 1e8;

            const now = new Date().toLocaleTimeString();
            
            // Limpa a linha e exibe os dois valores
            process.stdout.write(
                `\r[${now}] BINANCE: $${binancePrice.toFixed(2)} | CHAINLINK: $${chainlinkPrice.toFixed(2)} `
            );
        } catch (err) {
            process.stdout.write(`\r[${new Date().toLocaleTimeString()}] Erro na Chainlink, reconectando... `);
        }
    }, 1000);

    ws.on("error", (err) => console.error("Erro WebSocket Binance:", err));
}
run();
'
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Encerrando monitoramento..."
    pkill -f "node" 2>/dev/null
    echo "Status: Parado."
}

# --- CONTROLE ---
case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}" ; exit 1 ;;
esac
