#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Predictor Pro QUANTUM | Motor de Microestrutura | Sincronia SP"
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");
const fs = require("fs");

async function run() {
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let chainlinkPrice = 0, lastChainlinkPrice = 0, currentPrice = 0;
    let bidQty = 0, askQty = 0, bestBid = 0, bestAsk = 0;
    let priceAtWindowStart = 0, lastWindowMinute = -1;
    let history2Sec = [];
    let buyAggression = 0, sellAggression = 0; // CVD Simulado
    let lastProbAlta = 0;
    let activeAlerts = { up: { total: 0, timer: null }, down: { total: 0, timer: null } };

    // Chainlink
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            const newPrice = Number(data[1]) / 1e8;
            if (newPrice !== chainlinkPrice) { lastChainlinkPrice = chainlinkPrice; chainlinkPrice = newPrice; }
        } catch (e) {}
    }, 5000);

    const ws = new WebSocket("wss://stream.binance.com:9443/stream?streams=btcusdt@aggTrade/btcusdt@depth5");

    ws.on("message", (data) => {
        const payload = JSON.parse(data);
        const stream = payload.stream;
        const msg = payload.data;

        // Análise de Profundidade
        if (stream === "btcusdt@depth5") {
            bidQty = msg.bids.reduce((a, b) => a + parseFloat(b[1]), 0);
            askQty = msg.asks.reduce((a, b) => a + parseFloat(b[1]), 0);
            bestBid = parseFloat(msg.bids[0][0]);
            bestAsk = parseFloat(msg.asks[0][0]);
        }

        // Análise de Fluxo de Ordens (Tape Reading)
        if (stream === "btcusdt@aggTrade") {
            currentPrice = parseFloat(msg.p);
            const qty = parseFloat(msg.q);
            const isBuyerMaker = msg.m; // m=true significa que a venda agrediu a compra

            // Acumula agressão nos últimos segundos
            if (!isBuyerMaker) buyAggression += qty; else sellAggression += qty;
            setTimeout(() => { if (!isBuyerMaker) buyAggression -= qty; else sellAggression -= qty; }, 3000);

            const now = new Date();
            const currentMinute = now.getMinutes();
            const windowStartMinute = Math.floor(currentMinute / 5) * 5;

            if (windowStartMinute !== lastWindowMinute) {
                if (lastWindowMinute !== -1 && priceAtWindowStart > 0) {
                    const diff = currentPrice - priceAtWindowStart;
                    const logMsg = `[${now.toLocaleTimeString()}] FIM: ${lastWindowMinute}m | Ini: $${priceAtWindowStart.toFixed(2)} | Fim: $${currentPrice.toFixed(2)} | Prob: ${lastProbAlta.toFixed(1)}%\n`;
                    fs.appendFileSync("historico_predicoes.txt", logMsg);
                }
                priceAtWindowStart = currentPrice;
                lastWindowMinute = windowStartMinute;
            }

            const timestamp = Date.now();
            history2Sec.push({ p: currentPrice, t: timestamp });
            history2Sec = history2Sec.filter(h => h.t > (timestamp - 3000));
            const oldPriceObj = history2Sec.find(h => h.t <= (timestamp - 2000)) || history2Sec[0];
            const instantDiff = currentPrice - oldPriceObj.p;

            if (Math.abs(instantDiff) >= 5) {
                const type = instantDiff >= 5 ? "up" : "down";
                activeAlerts[type].total += Math.abs(instantDiff);
                process.stdout.write("\x07");
                clearTimeout(activeAlerts[type].timer);
                activeAlerts[type].timer = setTimeout(() => { activeAlerts[type].total = 0; }, 5000);
            }

            // --- NOVO MOTOR QUANTUM ---
            const elapsedSec = (now.getMinutes() % 5) * 60 + now.getSeconds();
            const progress = elapsedSec / 300;
            const secToWindow = 300 - elapsedSec;

            // 1. Score de Agressividade (Tape Reading) - Peso 30%
            const aggressionScore = buyAggression / (buyAggression + sellAggression || 1);
            
            // 2. Score de Book (Liquidez) - Peso 30%
            const bookScore = bidQty / (bidQty + askQty || 1);

            // 3. Score de Janela (Price Action) - Peso 30%
            // Inclui "Aceleração": se o preço atual está muito longe do início, a força aumenta
            const trendScore = currentPrice >= priceAtWindowStart ? 1 : 0;
            
            // 4. Score Oráculo (Arbitragem) - Peso 10%
            const oracleScore = chainlinkPrice >= currentPrice ? 1 : 0;

            // Cálculo Final com Decaimento Temporal
            // No final do ciclo, a Agressividade e a Tendência mandam mais que o Book parado.
            const pAlta = (aggressionScore * 0.35) + (bookScore * (0.25 - (progress * 0.15))) + (trendScore * (0.3 + (progress * 0.1))) + (oracleScore * 0.1);
            
            const probAlta = pAlta * 100;
            lastProbAlta = probAlta;
            const probQueda = 100 - probAlta;

            // UI
            const timeStr = now.toLocaleTimeString("pt-BR", { hour12: false });
            const diffWindow = currentPrice - priceAtWindowStart;
            const pctWindow = (diffWindow / priceAtWindowStart) * 100;
            const windowColor = diffWindow >= 0 ? "\x1b[32m" : "\x1b[31m";
            const mid = (bestBid + bestAsk) / 2;
            const binanceColor = currentPrice >= mid ? "\x1b[32m" : "\x1b[31m";
            
            let probStyle = "";
            if (secToWindow <= 10) probStyle = (now.getSeconds() % 2 === 0) ? "\x1b[7m\x1b[1m" : "\x1b[1m";

            const alertDisplay = (activeAlerts.up.total > 0 ? `\x1b[42m\x1b[30m ↑ +$${activeAlerts.up.total.toFixed(2)} \x1b[0m ` : "") +
                               (activeAlerts.down.total > 0 ? `\x1b[41m\x1b[37m ↓ -$${activeAlerts.down.total.toFixed(2)} \x1b[0m` : "");

            process.stdout.write(`\r\x1b[K[${timeStr}] Ini: $${priceAtWindowStart.toFixed(2)} | BINANCE: ${binanceColor}$${currentPrice.toFixed(2)}\x1b[0m | Janela: ${windowColor}${(diffWindow>=0?"+":"")}$${Math.abs(diffWindow).toFixed(2)} (${(pctWindow>=0?"+":"")}${pctWindow.toFixed(3)}%)\x1b[0m\n`);
            process.stdout.write(`\x1b[K${probStyle}PROB. FIM (${secToWindow}s): ${probAlta > 50 ? "\x1b[32m" : "\x1b[31m"}ALTA ${probAlta.toFixed(1)}% | QUEDA ${probQueda.toFixed(1)}%\x1b[0m${probStyle.length>0?"\x1b[0m":""}  ${alertDisplay}\x1b[1F`);
        }
    });

    ws.on("close", () => setTimeout(run, 1000));
}
run();
'
}

stop() {
    pkill -f "node" 2>/dev/null
    echo "Monitor parado."
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}" ;;
esac
