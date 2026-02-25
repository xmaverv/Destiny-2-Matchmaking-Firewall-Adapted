#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Monitor Master: Binance Book Colors + Chainlink Trend + Alertas Agrupados"
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
    let history5Min = [];
    let history2Sec = [];
    
    let activeAlerts = {
        up: { total: 0, timer: null },
        down: { total: 0, timer: null }
    };

    // 1. Chainlink com detecção de tendência (Cima/Baixo)
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

    // 2. Histórico temporal
    setInterval(() => {
        if (currentPrice > 0) {
            history5Min.push(currentPrice);
            if (history5Min.length > 300) history5Min.shift();
            history2Sec.push(currentPrice);
            if (history2Sec.length > 2) history2Sec.shift();
        }
    }, 1000);

    // 3. WebSocket Binance - Combinando Trades e Book
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
            const now = new Date().toLocaleTimeString("pt-BR", { hour12: false });
            
            // Lógica de Alerta de $5
            const price2sAgo = history2Sec[0] || currentPrice;
            const instantDiff = currentPrice - price2sAgo;

            if (Math.abs(instantDiff) >= 5) {
                const type = instantDiff >= 5 ? "up" : "down";
                activeAlerts[type].total += Math.abs(instantDiff);
                clearTimeout(activeAlerts[type].timer);
                activeAlerts[type].timer = setTimeout(() => { activeAlerts[type].total = 0; }, 5000);
            }

            // COR BINANCE (Baseada no Book: mais perto do Bid = Verde, mais perto do Ask = Vermelho)
            let binanceColor = "\x1b[37m"; // Branco padrão
            if (bestBid > 0 && bestAsk > 0) {
                const mid = (bestBid + bestAsk) / 2;
                binanceColor = currentPrice >= mid ? "\x1b[32m" : "\x1b[31m";
            }

            // COR CHAINLINK (Baseada no último preço)
            let clColor = "\x1b[37m";
            if (lastChainlinkPrice > 0) {
                clColor = chainlinkPrice >= lastChainlinkPrice ? "\x1b[32m" : "\x1b[31m";
            }

            // Cálculo 5 min
            let pct5min = 0;
            if (history5Min[0] > 0) pct5min = ((currentPrice - history5Min[0]) / history5Min[0]) * 100;
            const pctColor = pct5min >= 0 ? "\x1b[32m+" : "\x1b[31m";

            // Alertas Visuais
            let alertDisplay = "";
            if (activeAlerts.up.total > 0) alertDisplay += `\x1b[42m\x1b[30m ↑ PUMP: $${activeAlerts.up.total.toFixed(2)} \x1b[0m  `;
            if (activeAlerts.down.total > 0) alertDisplay += `\x1b[41m\x1b[37m ↓ DUMP: $${activeAlerts.down.total.toFixed(2)} \x1b[0m  `;

            // Print Final
            const line1 = `\r\x1b[K[${now}] BINANCE: ${binanceColor}$${currentPrice.toFixed(2)}\x1b[0m | 5m: ${pctColor}${pct5min.toFixed(3)}%\x1b[0m | CL: ${clColor}$${chainlinkPrice.toFixed(2)}\x1b[0m`;
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
