#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Iniciando Sistema Híbrido Completo [Binance + Chainlink + Predictor]"
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");

async function run() {
    // 1. Configurações de Conexão
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    // 2. Estado Global
    let chainlinkPrice = 0, lastChainlinkPrice = 0, currentPrice = 0;
    let bidQty = 0, askQty = 0, bestBid = 0, bestAsk = 0;
    let priceAtWindowStart = 0, lastWindowMinute = -1;
    let history2Sec = [];
    let activeAlerts = { 
        up: { total: 0, timer: null }, 
        down: { total: 0, timer: null } 
    };

    // 3. Loop Chainlink (A cada 5s)
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

    // 4. Loop de Tempo e Janela (Relógio de São Paulo)
    setInterval(() => {
        const now = new Date();
        const currentMinute = now.getMinutes();
        const windowStartMinute = Math.floor(currentMinute / 5) * 5;

        if (windowStartMinute !== lastWindowMinute) {
            priceAtWindowStart = currentPrice;
            lastWindowMinute = windowStartMinute;
        }

        if (currentPrice > 0) {
            history2Sec.push(currentPrice);
            if (history2Sec.length > 2) history2Sec.shift();
        }
    }, 1000);

    // 5. WebSocket Único (Combined Stream: Trades + Order Book Depth)
    const ws = new WebSocket("wss://stream.binance.com:9443/stream?streams=btcusdt@aggTrade/btcusdt@depth5");

    ws.on("message", (data) => {
        const payload = JSON.parse(data);
        const stream = payload.stream;
        const msg = payload.data;

        // Processa dados do Livro de Ordens (Pressão de Compra/Venda)
        if (stream === "btcusdt@depth5") {
            bidQty = msg.bids.reduce((a, b) => a + parseFloat(b[1]), 0);
            askQty = msg.asks.reduce((a, b) => a + parseFloat(b[1]), 0);
            bestBid = parseFloat(msg.bids[0][0]);
            bestAsk = parseFloat(msg.asks[0][0]);
        }

        // Processa cada Negócio (Frenético)
        if (stream === "btcusdt@aggTrade") {
            currentPrice = parseFloat(msg.p);
            if (priceAtWindowStart === 0) priceAtWindowStart = currentPrice;

            const now = new Date().toLocaleTimeString("pt-BR", { hour12: false });
            
            // Lógica de Alerta de $5 em 2s (Acumulativo)
            const price2sAgo = history2Sec[0] || currentPrice;
            const instantDiff = currentPrice - price2sAgo;
            if (Math.abs(instantDiff) >= 5) {
                const type = instantDiff >= 5 ? "up" : "down";
                activeAlerts[type].total += Math.abs(instantDiff);
                process.stdout.write("\x07"); // BIP
                clearTimeout(activeAlerts[type].timer);
                activeAlerts[type].timer = setTimeout(() => { activeAlerts[type].total = 0; }, 5000);
            }

            // --- MOTOR DE PROBABILIDADE ---
            const totalQty = bidQty + askQty;
            const bookPressure = totalQty > 0 ? (bidQty / totalQty) * 40 : 20; // 40% peso
            const windowDiff = currentPrice - priceAtWindowStart;
            const windowMomentum = windowDiff > 0 ? 35 : (windowDiff < 0 ? 5 : 20); // 40% peso
            const clDiff = chainlinkPrice - currentPrice;
            const clPressure = clDiff > 0 ? 15 : (clDiff < 0 ? 5 : 10); // 20% peso
            
            const probAlta = bookPressure + windowMomentum + clPressure;
            const probQueda = 100 - probAlta;

            // --- CORES E UI ---
            const mid = (bestBid + bestAsk) / 2;
            const binanceColor = currentPrice >= mid ? "\x1b[32m" : "\x1b[31m";
            const clColor = chainlinkPrice >= lastChainlinkPrice ? "\x1b[32m" : "\x1b[31m";
            const probColor = probAlta > 55 ? "\x1b[32m" : (probAlta < 45 ? "\x1b[31m" : "\x1b[33m");
            const pctWindow = ((currentPrice - priceAtWindowStart) / priceAtWindowStart) * 100;

            const alertDisplay = (activeAlerts.up.total > 0 ? `\x1b[42m\x1b[30m ↑ +$${activeAlerts.up.total.toFixed(2)} \x1b[0m ` : "") +
                               (activeAlerts.down.total > 0 ? `\x1b[41m\x1b[37m ↓ -$${activeAlerts.down.total.toFixed(2)} \x1b[0m` : "");

            // Saída de 2 linhas limpa
            const line1 = `\r\x1b[K[${now}] BINANCE: ${binanceColor}$${currentPrice.toFixed(2)}\x1b[0m | Janela 5m: ${(pctWindow>=0?"+":"")}${pctWindow.toFixed(3)}% | CL: ${clColor}$${chainlinkPrice.toFixed(2)}\x1b[0m`;
            const line2 = `\n\x1b[KPROB. FIM DE CICLO: ${probColor}ALTA ${probAlta.toFixed(1)}% | QUEDA ${probQueda.toFixed(1)}%\x1b[0m  ${alertDisplay}`;
            
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
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}" ;;
esac
