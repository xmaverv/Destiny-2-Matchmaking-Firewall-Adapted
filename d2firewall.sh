#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Predictor Pro [ULTIMATE] | Alerta de Fechamento | Sincronia SP"
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");

async function run() {
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let chainlinkPrice = 0, lastChainlinkPrice = 0, currentPrice = 0;
    let bidQty = 0, askQty = 0, bestBid = 0, bestAsk = 0;
    let priceAtWindowStart = 0, lastWindowMinute = -1;
    let history2Sec = [];
    let activeAlerts = { up: { total: 0, timer: null }, down: { total: 0, timer: null } };

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

        if (stream === "btcusdt@depth5") {
            bidQty = msg.bids.reduce((a, b) => a + parseFloat(b[1]), 0);
            askQty = msg.asks.reduce((a, b) => a + parseFloat(b[1]), 0);
            bestBid = parseFloat(msg.bids[0][0]);
            bestAsk = parseFloat(msg.asks[0][0]);
        }

        if (stream === "btcusdt@aggTrade") {
            currentPrice = parseFloat(msg.p);
            const now = new Date();
            
            // 1. SINCRONIA DE JANELA FIXA
            const currentMinute = now.getMinutes();
            const windowStartMinute = Math.floor(currentMinute / 5) * 5;
            if (windowStartMinute !== lastWindowMinute) {
                priceAtWindowStart = currentPrice;
                lastWindowMinute = windowStartMinute;
            }
            if (priceAtWindowStart === 0) priceAtWindowStart = currentPrice;

            // 2. ALERTAS $5
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

            // 3. MOTOR DE PROBABILIDADE
            const elapsedSec = (now.getMinutes() % 5) * 60 + now.getSeconds();
            const progress = elapsedSec / 300;
            const secToWindow = 300 - elapsedSec;

            const weightBook = 0.5 * (1 - (progress * 0.5));
            const weightTrend = 0.3 + (progress * 0.4);
            const weightOracle = 1 - (weightBook + weightTrend);

            const bookScore = bidQty / (bidQty + askQty || 1);
            const trendScore = currentPrice >= priceAtWindowStart ? 1 : 0;
            const oracleScore = chainlinkPrice >= currentPrice ? 1 : 0;

            const probAlta = (bookScore * weightBook + trendScore * weightTrend + oracleScore * weightOracle) * 100;
            const probQueda = 100 - probAlta;

            // 4. UI E CORES
            const timeStr = now.toLocaleTimeString("pt-BR", { hour12: false });
            const mid = (bestBid + bestAsk) / 2;
            const binanceColor = currentPrice >= mid ? "\x1b[32m" : "\x1b[31m";
            const clColor = chainlinkPrice >= lastChainlinkPrice ? "\x1b[32m" : "\x1b[31m";
            const pctWindow = ((currentPrice - priceAtWindowStart) / priceAtWindowStart) * 100;
            const windowColor = pctWindow >= 0 ? "\x1b[32m" : "\x1b[31m";

            // LOGICA DE PISCAR NOS ULTIMOS 10s
            let probColor = probAlta > 55 ? "\x1b[32m" : (probAlta < 45 ? "\x1b[31m" : "\x1b[33m");
            let probStyle = "";
            if (secToWindow <= 10) {
                // Efeito invertido piscante para atenção total
                probStyle = (now.getSeconds() % 2 === 0) ? "\x1b[7m\x1b[1m" : "\x1b[1m";
            }

            const alertDisplay = (activeAlerts.up.total > 0 ? `\x1b[42m\x1b[30m ↑ PUMP +$${activeAlerts.up.total.toFixed(2)} \x1b[0m ` : "") +
                               (activeAlerts.down.total > 0 ? `\x1b[41m\x1b[37m ↓ DUMP -$${activeAlerts.down.total.toFixed(2)} \x1b[0m` : "");

            // OUTPUT
            process.stdout.write(`\r\x1b[K[${timeStr}] BINANCE: ${binanceColor}$${currentPrice.toFixed(2)}\x1b[0m | Janela 5m: ${windowColor}${(pctWindow>=0?"+":"")}${pctWindow.toFixed(3)}%\x1b[0m | CL: ${clColor}$${chainlinkPrice.toFixed(2)}\x1b[0m\n`);
            process.stdout.write(`\x1b[K${probStyle}PROB. FECHAMENTO (${secToWindow}s): ${probColor}ALTA ${probAlta.toFixed(1)}% | QUEDA ${probQueda.toFixed(1)}%\x1b[0m${probStyle.length>0?"\x1b[0m":""}  ${alertDisplay}\x1b[1F`);
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
