#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Monitor de Alta Volatilidade: Binance + Alerta Real \$5 + Polymarket 5min"
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");

async function run() {
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let chainlinkPrice = 0;
    let currentPrice = 0;
    let referencePrice = 0; // Preço base para o alerta de $5
    let price5MinAgo = 0;
    let history5Min = [];

    // 1. Chainlink (Atualiza a cada 5s)
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            chainlinkPrice = Number(data[1]) / 1e8;
        } catch (e) {}
    }, 5000);

    // 2. Lógica Polymarket (Janela de 5 minutos)
    setInterval(() => {
        if (currentPrice > 0) {
            history5Min.push(currentPrice);
            if (history5Min.length > 300) history5Min.shift();
            price5MinAgo = history5Min[0];
        }
    }, 1000);

    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@aggTrade");

    ws.on("message", (data) => {
        const msg = JSON.parse(data);
        currentPrice = parseFloat(msg.p);
        
        // Inicializa o preço de referência no primeiro trade
        if (referencePrice === 0) referencePrice = currentPrice;

        const now = new Date().toLocaleTimeString("pt-BR", { hour12: false });
        let alertMessage = "";

        // CALCULA MOVIMENTO ABRUPTO ($5 em relação à última referência)
        const priceDiff = currentPrice - referencePrice;
        
        if (Math.abs(priceDiff) >= 5) {
            const direction = priceDiff >= 5 ? "PUMP ↑" : "DUMP ↓";
            const alertColor = priceDiff >= 5 ? "\x1b[42m" : "\x1b[41m"; // Verde para Pump, Vermelho para Dump
            
            // Mensagem de Alerta que ficará visível
            alertMessage = `${alertColor}!! ${direction} $${Math.abs(priceDiff).toFixed(2)} !!\x1b[0m `;
            
            // Emite BIP sonoro
            process.stdout.write("\x07");
            
            // Atualiza a referência para o novo patamar
            referencePrice = currentPrice;
        }

        // Porcentagem 5 min
        let pct5min = 0;
        if (price5MinAgo > 0) {
            pct5min = ((currentPrice - price5MinAgo) / price5MinAgo) * 100;
        }
        const pctColor = pct5min >= 0 ? "\x1b[32m+" : "\x1b[31m";

        // Saída do terminal
        process.stdout.write(
            `\r\x1b[K[${now}] ${alertMessage}BINANCE: $${currentPrice.toFixed(2)} | ` +
            `5min: ${pctColor}${pct5min.toFixed(3)}%\x1b[0m | ` +
            `REF: $${referencePrice.toFixed(0)} | ` +
            `CL: $${chainlinkPrice.toFixed(2)}`
        );
    });

    ws.on("close", () => setTimeout(run, 1000));
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
