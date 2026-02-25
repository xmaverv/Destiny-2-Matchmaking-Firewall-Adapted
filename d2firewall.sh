#!/bin/bash

PROJETO_DIR="/home/ubuntu/meu-projeto"

start() {
    echo "Iniciando Monitor Ultra-Frenético (Binance Trades + Chainlink)..."
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");
const WebSocket = require("ws");

async function run() {
    // Configuração Chainlink (Estático, atualiza a cada 5s para não sobrecarregar a RPC)
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let chainlinkPrice = 0;
    let lastBinancePrice = 0;

    // Busca Chainlink em background
    setInterval(async () => {
        try {
            const data = await priceFeed.latestRoundData();
            chainlinkPrice = Number(data[1]) / 1e8;
        } catch (e) {}
    }, 5000);

    // Stream de NEGÓCIOS EM TEMPO REAL (Aggregated Trades)
    // Esse é o stream mais rápido disponível para usuários públicos
    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@aggTrade");

    ws.on("message", (data) => {
        const msg = JSON.parse(data);
        const currentPrice = parseFloat(msg.p); // "p" é o preço do trade real
        const quantity = parseFloat(msg.q);    // "q" é a quantidade negociada
        
        const now = new Date().toLocaleTimeString("pt-BR", { hour12: false }) + "." + new Date().getMilliseconds();
        
        // Lógica de cores baseada no movimento do trade
        let color = "\x1b[32m"; // Verde (Subiu ou igual)
        if (currentPrice < lastBinancePrice) {
            color = "\x1b[31m"; // Vermelho (Caiu)
        }

        const diff = chainlinkPrice > 0 ? (currentPrice - chainlinkPrice) : 0;

        // Saída frenética com milissegundos e quantidade do trade
        process.stdout.write(
            `\r\x1b[K[${now}] ${color}BINANCE: $${currentPrice.toFixed(2)}\x1b[0m (Vol: ${quantity.toFixed(4)}) | CHAINLINK: $${chainlinkPrice.toFixed(2)} | DIFF: $${diff.toFixed(2)}`
        );
        
        lastBinancePrice = currentPrice;
    });

    ws.on("close", () => {
        console.log("\nConexão fechada. Reiniciando...");
        setTimeout(run, 1000);
    });
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
