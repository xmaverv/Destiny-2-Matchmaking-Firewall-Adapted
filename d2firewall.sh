#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Monitor Avançado: Binance (Frenético) + Alerta \$5 + Polymarket 5min Style"
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");

async function run() {
    // Configuração Chainlink
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let chainlinkPrice = 0;
    let lastPrice = 0;
    let price5MinAgo = 0;
    let history5Min = [];

    // 1. Atualiza Chainlink a cada 5s
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            chainlinkPrice = Number(data[1]) / 1e8;
        } catch (e) {}
    }, 5000);

    // 2. Lógica Polymarket (Variação de 5 minutos)
    // Armazena o preço a cada segundo em um array de 300 posições (5 min)
    setInterval(() => {
        if (lastPrice > 0) {
            history5Min.push(lastPrice);
            if (history5Min.length > 300) history5Min.shift();
            price5MinAgo = history5Min[0];
        }
    }, 1000);

    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@aggTrade");

    ws.on("message", (data) => {
        const msg = JSON.parse(data);
        const currentPrice = parseFloat(msg.p);
        const now = new Date();
        const timeStr = now.toLocaleTimeString("pt-BR", { hour12: false });

        // Cálculo de Movimento Abrupto (Delta $5)
        let alert = "";
        if (lastPrice > 0 && Math.abs(currentPrice - lastPrice) >= 5) {
            alert = `\x07 \x1b[41m[ALERTA: MOVIMENTO > $5]\x1b[0m `; // \x07 emite o BIP sonoro
        }

        // Cálculo de Porcentagem 5 min (Estilo Polymarket)
        let pct5min = 0;
        if (price5MinAgo > 0) {
            pct5min = ((currentPrice - price5MinAgo) / price5MinAgo) * 100;
        }
        const pctColor = pct5min >= 0 ? "\x1b[32m+" : "\x1b[31m";

        // Cor do preço (Binance)
        const priceColor = currentPrice >= lastPrice ? "\x1b[32m" : "\x1b[31m";

        process.stdout.write(
            `\r\x1b[K[${timeStr}] ${alert}${priceColor}BINANCE: $${currentPrice.toFixed(2)}\x1b[0m | ` +
            `5min: ${pctColor}${pct5min.toFixed(3)}%\x1b[0m | ` +
            `CHAINLINK: $${chainlinkPrice.toFixed(2)}`
        );

        lastPrice = currentPrice;
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
