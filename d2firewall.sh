#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Monitor de Volatilidade Instantânea: Alerta \$5 em 2s | Polymarket 5min"
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
    let price5MinAgo = 0;
    let history5Min = [];
    let history2Sec = []; // Janela para o alerta de 2 segundos

    // 1. Chainlink (Atualiza a cada 5s)
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            chainlinkPrice = Number(data[1]) / 1e8;
        } catch (e) {}
    }, 5000);

    // 2. Histórico para as métricas de tempo (1s e 5min)
    setInterval(() => {
        if (currentPrice > 0) {
            // Janela de 5 minutos (300 amostras)
            history5Min.push(currentPrice);
            if (history5Min.length > 300) history5Min.shift();
            price5MinAgo = history5Min[0];

            // Janela de Alerta Instantâneo (2 amostras = 2 segundos)
            history2Sec.push(currentPrice);
            if (history2Sec.length > 2) history2Sec.shift();
        }
    }, 1000);

    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@aggTrade");

    ws.on("message", (data) => {
        const msg = JSON.parse(data);
        currentPrice = parseFloat(msg.p);
        const now = new Date().toLocaleTimeString("pt-BR", { hour12: false });
        
        let alertMessage = "";
        const price2sAgo = history2Sec[0] || currentPrice;
        const instantDiff = currentPrice - price2sAgo;

        // LÓGICA DE ALERTA: $5 de movimento em relação ao preço de 2 segundos atrás
        if (Math.abs(instantDiff) >= 5) {
            const direction = instantDiff >= 5 ? "FOGUETE ↑" : "QUEDA LIVRE ↓";
            const alertColor = instantDiff >= 5 ? "\x1b[42m" : "\x1b[41m"; // Fundo Verde ou Vermelho
            
            // Exibe o alerta em uma linha nova para não perder o histórico visual
            process.stdout.write(`\n\x07${alertColor}[MOVIMENTO ABRUPTO: ${direction} $${Math.abs(instantDiff).toFixed(2)} em 2s]\x1b[0m\n`);
        }

        // Porcentagem 5 min (Estilo Polymarket)
        let pct5min = 0;
        if (price5MinAgo > 0) {
            pct5min = ((currentPrice - price5MinAgo) / price5MinAgo) * 100;
        }
        const pctColor = pct5min >= 0 ? "\x1b[32m+" : "\x1b[31m";

        // Saída frenética
        process.stdout.write(
            `\r\x1b[K[${now}] BINANCE: $${currentPrice.toFixed(2)} | 5min: ${pctColor}${pct5min.toFixed(3)}%\x1b[0m | CL: $${chainlinkPrice.toFixed(2)}`
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
    *) echo "Uso: $0 {start|stop}" ;;
esac
