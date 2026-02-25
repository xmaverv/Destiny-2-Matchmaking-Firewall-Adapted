#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Monitor Profissional: Agregação de Movimento + Alertas Direcionais"
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
    let history5Min = [];
    let history2Sec = [];
    
    // Objetos para rastrear alertas ativos por direção
    let activeAlerts = {
        up: { total: 0, timer: null, startTime: 0 },
        down: { total: 0, timer: null, startTime: 0 }
    };

    // 1. Chainlink (Background)
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            chainlinkPrice = Number(data[1]) / 1e8;
        } catch (e) {}
    }, 5000);

    // 2. Histórico (1s)
    setInterval(() => {
        if (currentPrice > 0) {
            history5Min.push(currentPrice);
            if (history5Min.length > 300) history5Min.shift();
            history2Sec.push(currentPrice);
            if (history2Sec.length > 2) history2Sec.shift();
        }
    }, 1000);

    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@aggTrade");

    ws.on("message", (data) => {
        const msg = JSON.parse(data);
        currentPrice = parseFloat(msg.p);
        const now = new Date().toLocaleTimeString("pt-BR", { hour12: false });
        
        const price2sAgo = history2Sec[0] || currentPrice;
        const instantDiff = currentPrice - price2sAgo;

        // LÓGICA DE SOMA/ACUMULAÇÃO DE MOVIMENTO
        if (Math.abs(instantDiff) >= 5) {
            const type = instantDiff >= 5 ? "up" : "down";
            
            // Se já houver um alerta dessa direção, somamos o valor
            activeAlerts[type].total += Math.abs(instantDiff);
            
            // Reinicia o cronômetro de 5 segundos para este alerta
            clearTimeout(activeAlerts[type].timer);
            activeAlerts[type].timer = setTimeout(() => {
                activeAlerts[type].total = 0;
            }, 5000);
            
            if (activeAlerts[type].total === Math.abs(instantDiff)) {
                 process.stdout.write("\x07"); // BIP apenas no primeiro disparo do acúmulo
            }
        }

        // Cálculo 5 min
        let pct5min = 0;
        if (history5Min[0] > 0) {
            pct5min = ((currentPrice - history5Min[0]) / history5Min[0]) * 100;
        }
        const pctColor = pct5min >= 0 ? "\x1b[32m+" : "\x1b[31m";

        // CONSTRUÇÃO DOS BLOCOS VISUAIS
        let alertDisplay = "";
        if (activeAlerts.up.total > 0) {
            alertDisplay += `\x1b[42m\x1b[30m ↑ PUMP: $${activeAlerts.up.total.toFixed(2)} \x1b[0m  `;
        }
        if (activeAlerts.down.total > 0) {
            alertDisplay += `\x1b[41m\x1b[37m ↓ DUMP: $${activeAlerts.down.total.toFixed(2)} \x1b[0m  `;
        }

        // IMPRESSÃO EM DUAS LINHAS
        // \x1b[K limpa a linha para evitar rastros
        const line1 = `\r\x1b[K[${now}] BINANCE: $${currentPrice.toFixed(2)} | 5m: ${pctColor}${pct5min.toFixed(3)}%\x1b[0m | CL: $${chainlinkPrice.toFixed(2)}`;
        const line2 = `\n\x1b[K${alertDisplay}`;
        
        process.stdout.write(line1 + line2 + "\x1b[1F"); 
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
