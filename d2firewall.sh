#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Predictor Pro FINAL | Cores Restauradas | Motor de Equilíbrio | Sincronia SP"
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
    let buyAggression = 0, sellAggression = 0;
    let lastProbAlta = 0;
    let activeAlerts = { up: { total: 0, timer: null }, down: { total: 0, timer: null } };

    // Oráculo Chainlink (Background)
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            const newPrice = Number(data[1]) / 1e8;
            if (newPrice !== chainlinkPrice) { 
                lastChainlinkPrice = chainlinkPrice; 
                chainlinkPrice = newPrice; 
            }
        } catch (e) {}
    }, 3000);

    const ws = new WebSocket("wss://stream.binance.com:9443/stream?streams=btcusdt@aggTrade/btcusdt@depth5");

    ws.on("message", (data) => {
        const payload = JSON.parse(data);
        const stream = payload.stream;
        const msg = payload.data;

        // Captura Profundidade do Book
        if (stream === "btcusdt@depth5") {
            bidQty = msg.bids.reduce((a, b) => a + parseFloat(b[1]), 0);
            askQty = msg.asks.reduce((a, b) => a + parseFloat(b[1]), 0);
            bestBid = parseFloat(msg.bids[0][0]);
            bestAsk = parseFloat(msg.asks[0][0]);
        }

        // Processamento de Trades
        if (stream === "btcusdt@aggTrade") {
            currentPrice = parseFloat(msg.p);
            const qty = parseFloat(msg.q);
            if (!msg.m) buyAggression += qty; else sellAggression += qty;
            setTimeout(() => { if (!msg.m) buyAggression -= qty; else sellAggression -= qty; }, 4000);

            const now = new Date();
            const currentMinute = now.getMinutes();
            const windowStartMinute = Math.floor(currentMinute / 5) * 5;

            // Logica de Janela Fixa (Relógio SP)
            if (windowStartMinute !== lastWindowMinute) {
                if (lastWindowMinute !== -1 && priceAtWindowStart > 0) {
                    const diff = currentPrice - priceAtWindowStart;
                    const logMsg = `[${now.toLocaleTimeString()}] FIM: ${lastWindowMinute}m | Ini: $${priceAtWindowStart} | Fim: $${currentPrice} | Prob: ${lastProbAlta.toFixed(1)}%\n`;
                    fs.appendFileSync("historico_predicoes.txt", logMsg);
                }
                priceAtWindowStart = currentPrice;
                lastWindowMinute = windowStartMinute;
            }
            if (priceAtWindowStart === 0) priceAtWindowStart = currentPrice;

            // Histórico Alertas $5
            const timestamp = Date.now();
            history2Sec.push({ p: currentPrice, t: timestamp });
            history2Sec = history2Sec.filter(h => h.t > (timestamp - 2000));
            const oldPrice = history2Sec[0].p;
            const instantDiff = currentPrice - oldPrice;

            if (Math.abs(instantDiff) >= 5) {
                const type = instantDiff >= 5 ? "up" : "down";
                activeAlerts[type].total += Math.abs(instantDiff);
                process.stdout.write("\x07"); 
                clearTimeout(activeAlerts[type].timer);
                activeAlerts[type].timer = setTimeout(() => { activeAlerts[type].total = 0; }, 5000);
            }

            // MOTOR DE PROBABILIDADE (Ciclo 5m)
            const elapsed = (now.getMinutes() % 5) * 60 + now.getSeconds();
            const progress = elapsed / 300;
            const secToWindow = 300 - elapsed;

            const scoreAgressao = buyAggression / (buyAggression + sellAggression || 1);
            const scoreBook = bidQty / (bidQty + askQty || 1);
            const scoreTendencia = currentPrice >= priceAtWindowStart ? 1 : 0;
            const oracleGap = chainlinkPrice - currentPrice;
            const scoreOracle = oracleGap > 0 ? 0.8 : (oracleGap < 0 ? 0.2 : 0.5);

            const pAlta = (scoreAgressao * 0.3) + 
                          (scoreBook * (0.3 * (1 - progress))) + 
                          (scoreTendencia * (0.25 + (progress * 0.15))) + 
                          (scoreOracle * 0.15);

            const probAlta = pAlta * 100;
            lastProbAlta = probAlta;
            const probQueda = 100 - probAlta;

            // --- FORMATAÇÃO VISUAL ---
            const timeStr = now.toLocaleTimeString("pt-BR", { hour12: false });
            const diffWin = currentPrice - priceAtWindowStart;
            const pctWin = (diffWin / priceAtWindowStart) * 100;
            const winColor = diffWin >= 0 ? "\x1b[32m" : "\x1b[31m";
            
            // COR BINANCE (Baseada no Spread)
            const mid = (bestBid + bestAsk) / 2;
            const binanceColor = currentPrice >= mid ? "\x1b[32m" : "\x1b[31m";
            
            // COR CHAINLINK (Baseada no movimento)
            const clColor = chainlinkPrice >= lastChainlinkPrice ? "\x1b[32m" : "\x1b[31m";
            
            let probStyle = "";
            if (secToWindow <= 10) probStyle = (now.getSeconds() % 2 === 0) ? "\x1b[7m\x1b[1m" : "\x1b[1m";

            const alertDisplay = (activeAlerts.up.total > 0 ? `\x1b[42m\x1b[30m ↑ +$${activeAlerts.up.total.toFixed(2)} \x1b[0m ` : "") +
                               (activeAlerts.down.total > 0 ? `\x1b[41m\x1b[37m ↓ -$${activeAlerts.down.total.toFixed(2)} \x1b[0m` : "");

            // OUTPUT
            process.stdout.write(`\r\x1b[K[${timeStr}] Ini: $${priceAtWindowStart.toFixed(2)} | BINANCE: ${binanceColor}$${currentPrice.toFixed(2)}\x1b[0m | Janela: ${winColor}${(diffWin>=0?"+":"")}$${Math.abs(diffWin).toFixed(2)} (${(pctWin>=0?"+":"")}${pctWin.toFixed(3)}%)\x1b[0m | CL: ${clColor}$${chainlinkPrice.toFixed(2)}\x1b[0m\n`);
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
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}" ;;
esac
