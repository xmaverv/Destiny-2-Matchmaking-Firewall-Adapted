#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Iniciando Monitor de Alta Velocidade: Binance Order Book + Chainlink..."
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");

async function run() {
    // Conexao Chainlink
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let chainlinkPrice = 0;
    let lastBinancePrice = 0;

    // Atualiza Chainlink em segundo plano a cada 1s (ela eh lenta por natureza)
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            chainlinkPrice = Number(data[1]) / 1e8;
        } catch (e) {}
    }, 1000);

    // Stream do Order Book (Best Bid/Ask) - Isso aqui eh instantaneo
    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@bookTicker");

    ws.on("message", (data) => {
        const msg = JSON.parse(data);
        const bestBid = parseFloat(msg.b); // Preco de compra no topo do book
        const bestAsk = parseFloat(msg.a); // Preco de venda no topo do book
        const midPrice = (bestBid + bestAsk) / 2;

        const now = new Date().toLocaleTimeString();
        
        // Calculo do Spread entre Binance e Chainlink
        const diff = chainlinkPrice > 0 ? (midPrice - chainlinkPrice) : 0;
        const color = midPrice >= lastBinancePrice ? "\x1b[32m" : "\x1b[31m"; // Verde se subir, vermelho se cair
        
        process.stdout.write(
            `\r[${now}] ${color}BINANCE (Book): $${midPrice.toFixed(2)}\x1b[0m | CHAINLINK: $${chainlinkPrice.toFixed(2)} | DIFF: $${diff.toFixed(2)}  `
        );
        
        lastBinancePrice = midPrice;
    });

    ws.on("error", () => {
        console.log("Erro no WebSocket. Tentando reconectar...");
        run();
    });
}
run();
'
}

stop() {
    echo "Parando monitoramento..."
    pkill -f "node" 2>/dev/null
    echo "Status: Parado."
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}" ;;
esac
