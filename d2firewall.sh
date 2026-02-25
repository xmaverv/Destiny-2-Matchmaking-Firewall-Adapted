#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Monitor Master: Janelas Fixas de 5min (Relógio SP) + Book Sentiment"
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
    let lastChainlinkPrice = 0;
    let currentPrice = 0;
    let bestBid = 0;
    let bestAsk = 0;
    
    // Lógica de Janela Fixa (Relógio Real)
    let priceAtWindowStart = 0;
    let lastWindowMinute = -1;

    let history2Sec = [];
    let activeAlerts = {
        up: { total: 0, timer: null },
        down: { total: 0, timer: null }
    };

    // 1. Chainlink (Background)
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            const newPrice = Number(data[1]) / 1e8;
            if (newPrice !== chainlinkPrice) {
                lastChainlinkPrice = chainlinkPrice;
                chainlinkPrice = newPrice;
            }
        } catch (e) {}
    }, 5000);

    // 2. Sincronização com o Relógio para Janela de 5min
    setInterval(() => {
        const now = new Date();
        const currentMinute = now.getMinutes();
        
        // Calcula o início da janela de 5 min (0, 5, 10, 15...)
        const windowStartMinute = Math.floor(currentMinute / 5) * 5;

        // Se mudamos de janela (ex: de 04:59 para 05:00), resetamos o preço base
        if (windowStartMinute !== lastWindowMinute) {
            priceAtWindowStart = currentPrice;
            lastWindowMinute = windowStartMinute;
        }

        // Histórico de 2s para alerta de volatilidade
        if (currentPrice > 0) {
            history2Sec.push(currentPrice);
            if (history2Sec.length > 2) history2Sec.shift();
        }
    }, 1000);

    // 3. WebSocket Binance
    const ws = new WebSocket("wss://stream.binance.com:9443/stream?streams=btcusdt@aggTrade/btcusdt@bookTicker");

    ws.on("message", (data) => {
        const payload = JSON.parse(data);
        const stream = payload.stream;
        const msg = payload.data;

        if (stream === "btcusdt@bookTicker") {
            bestBid = parseFloat(msg.b);
            bestAsk = parseFloat(msg.a);
        }

        if (stream === "btcusdt@aggTrade") {
            currentPrice = parseFloat(msg.p);
            if (priceAtWindowStart === 0) priceAtWindowStart = currentPrice;

            const now = new Date();
            const timeStr = now.toLocaleTimeString("pt-BR", { hour12: false });
            
            // Lógica de Alerta de $5 em 2s
            const price2sAgo = history2Sec[0] || currentPrice;
            const instantDiff = currentPrice - price2sAgo;

            if (Math.abs(instantDiff) >= 5) {
                const type = instantDiff >= 5 ? "up" : "down";
                activeAlerts[type].total += Math.abs(instantDiff);
                clearTimeout(activeAlerts[type].timer);
                activeAlerts[type].timer = setTimeout(() => { activeAlerts[type].total = 0; }, 5000);
            }

            // Cores baseadas no Order Book e Tendência Chainlink
            const mid = (bestBid + bestAsk) / 2;
            const binanceColor = currentPrice >= mid ? "\x1b[32m" : "\x1b[31m";
            const clColor = chainlinkPrice >= lastChainlinkPrice ? "\x1b[32m" : "\x1b[31m";

            // Cálculo da Porcentagem da JANELA ATUAL (ex: desde 10:00:00)
            const pctWindow = ((currentPrice - priceAtWindowStart) / priceAtWindowStart) * 100;
            const pctColor = pctWindow >= 0 ? "\x1b[32m+" : "\x1b[31m";

            // Alertas
            let alertDisplay = "";
            if (activeAlerts.up.total > 0) alertDisplay += `\x1b[42m\x1b[30m ↑ PUMP: $${activeAlerts.up.total.toFixed(2)} \x1b[0m  `;
            if (activeAlerts.down.total > 0) alertDisplay += `\x1b[41m\x1b[37m ↓ DUMP: $${activeAlerts.down.total.toFixed(2)} \x1b[0m  `;

            // Interface
            const line1 = `\r\x1b[K[${timeStr}] BINANCE: ${binanceColor}$${currentPrice.toFixed(2)}\x1b[0m | Janela 5m: ${pctColor}${pctWindow.toFixed(3)}%\x1b[0m | CL: ${clColor}$${chainlinkPrice.toFixed(2)}\x1b[0m`;
            const line2 = `\n\x1b[K${alertDisplay}`;
            
            process.stdout.write(line1 + line2 + "\x1b[1F");
        }
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
    *) echo "Uso: $0 {start|stop}" ;;
esac
