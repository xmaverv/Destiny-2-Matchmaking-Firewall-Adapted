#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Iniciando Predictor Pro: Janelas Fixas de Relógio + Motor de Alta Precisão"
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

    // 1. Chainlink (Background)
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            const newPrice = Number(data[1]) / 1e8;
            if (newPrice !== chainlinkPrice) { lastChainlinkPrice = chainlinkPrice; chainlinkPrice = newPrice; }
        } catch (e) {}
    }, 5000);

    // 2. WebSocket Combined (aggTrade + depth5)
    const ws = new WebSocket("wss://stream.binance.com:9443/stream?streams=btcusdt@aggTrade/btcusdt@depth5");

    ws.on("message", (data) => {
        const payload = JSON.parse(data);
        const stream = payload.stream;
        const msg = payload.data;

        // CAPTURA DE BOOK (Depth 5)
        if (stream === "btcusdt@depth5") {
            bidQty = msg.bids.reduce((a, b) => a + parseFloat(b[1]), 0);
            askQty = msg.asks.reduce((a, b) => a + parseFloat(b[1]), 0);
            bestBid = parseFloat(msg.bids[0][0]);
            bestAsk = parseFloat(msg.asks[0][0]);
        }

        // PROCESSAMENTO DE TRADE E RELÓGIO
        if (stream === "btcusdt@aggTrade") {
            currentPrice = parseFloat(msg.p);
            
            // --- SINCRONIZAÇÃO RELÓGIO FIXO (SP) ---
            const now = new Date();
            const currentMinute = now.getMinutes();
            const windowStartMinute = Math.floor(currentMinute / 5) * 5;

            // Reset Crítico: Se o minuto do relógio mudou para um múltiplo de 5, fixa novo preço base
            if (windowStartMinute !== lastWindowMinute) {
                priceAtWindowStart = currentPrice;
                lastWindowMinute = windowStartMinute;
            }

            // Histórico rápido (2s)
            history2Sec.push({ p: currentPrice, t: Date.now() });
            if (history2Sec.length > 20) history2Sec.shift(); // Aumentado para rastrear momentum

            // Alerta de $5 em 2s
            const oldPriceObj = history2Sec.find(h => h.t <= (Date.now() - 2000)) || history2Sec[0];
            const instantDiff = currentPrice - oldPriceObj.p;
            if (Math.abs(instantDiff) >= 5) {
                const type = instantDiff >= 5 ? "up" : "down";
                activeAlerts[type].total += Math.abs(instantDiff);
                process.stdout.write("\x07"); 
                clearTimeout(activeAlerts[type].timer);
                activeAlerts[type].timer = setTimeout(() => { activeAlerts[type].total = 0; }, 5000);
            }

            // --- MOTOR DE PROBABILIDADE AVANÇADO ---
            // 1. Intensidade do Book (0-45%): Relação entre Bids e Asks
            const bookImbalance = bidQty / (bidQty + askQty);
            const scoreBook = bookImbalance * 45;

            // 2. Velocity Momentum (0-35%): Aceleração do preço nos últimos 2s
            const velocity = (currentPrice - oldPriceObj.p);
            const scoreVelocity = velocity > 0 ? 35 : (velocity < 0 ? 0 : 17.5);

            // 3. Oráculo Bias (0-20%): Distância para o preço "Justo" da Chainlink
            const clGap = chainlinkPrice - currentPrice;
            const scoreOraculo = clGap > 1 ? 20 : (clGap < -1 ? 0 : 10);

            const probAlta = scoreBook + scoreVelocity + scoreOraculo;
            const probQueda = 100 - probAlta;

            // --- UI ---
            const timeStr = now.toLocaleTimeString("pt-BR", { hour12: false });
            const secToWindow = 300 - ((now.getMinutes() % 5) * 60 + now.getSeconds());
            const mid = (bestBid + bestAsk) / 2;
            const binanceColor = currentPrice >= mid ? "\x1b[32m" : "\x1b[31m";
            const clColor = chainlinkPrice >= lastChainlinkPrice ? "\x1b[32m" : "\x1b[31m";
            const probColor = probAlta > 55 ? "\x1b[32m" : (probAlta < 45 ? "\x1b[31m" : "\x1b[33m");
            const pctWindow = ((currentPrice - priceAtWindowStart) / priceAtWindowStart) * 100;

            const alertDisplay = (activeAlerts.up.total > 0 ? `\x1b[42m\x1b[30m ↑ +$${activeAlerts.up.total.toFixed(2)} \x1b[0m ` : "") +
                               (activeAlerts.down.total > 0 ? `\x1b[41m\x1b[37m ↓ -$${activeAlerts.down.total.toFixed(2)} \x1b[0m` : "");

            const line1 = `\r\x1b[K[${timeStr}] BINANCE: ${binanceColor}$${currentPrice.toFixed(2)}\x1b[0m | Janela 5m: ${(pctWindow>=0?"+":"")}${pctWindow.toFixed(3)}% | CL: ${clColor}$${chainlinkPrice.toFixed(2)}\x1b[0m`;
            const line2 = `\n\x1b[KPROB. FECHAMENTO (${secToWindow}s): ${probColor}ALTA ${probAlta.toFixed(1)}% | QUEDA ${probQueda.toFixed(1)}%\x1b[0m  ${alertDisplay}`;
            
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
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}" ;;
esac
