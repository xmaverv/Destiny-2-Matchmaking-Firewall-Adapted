#!/bin/bash

# --- CONFIGURAÇÃO ---
PROJETO_DIR="/home/ubuntu/meu-projeto"

# --- FUNÇÃO START ---
start() {
    echo "Monitorando Preço Agregado (Binance/Exchanges) via Chainlink..."
    echo "Pressione CTRL+C para sair."
    
    cd "$PROJETO_DIR" || exit 1

    node -e '
const { ethers } = require("ethers");

async function run() {
    // Usando uma RPC robusta para evitar travamentos em 1s
    const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
    
    // Contrato Chainlink BTC/USD (Agregador que inclui Binance)
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const abi = ["function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)"];
    const priceFeed = new ethers.Contract(btcUsdAddress, abi, provider);

    let lastPrice = 0;

    setInterval(async () => {
        try {
            const roundData = await priceFeed.latestRoundData();
            const price = Number(roundData[1]) / 1e8;
            const now = new Date().toLocaleTimeString();
            
            // Define uma cor se o preço mudar (Verde para subida/estável, Amarelo para alteração)
            let color = "\x1b[32m"; // Verde
            if (price !== lastPrice && lastPrice !== 0) {
                color = "\x1b[33m"; // Amarelo se houver oscilação
            }
            
            lastPrice = price;

            // Mostra o preço com 2 casas decimais e o timestamp exato
            process.stdout.write(`\r${color}[${now}] BINANCE/CHAINLINK BTC: $${price.toFixed(2)}\x1b[0m `);
            
        } catch (err) {
            process.stdout.write(`\r\x1b[31m[${new Date().toLocaleTimeString()}] Erro na rede...\x1b[0m `);
        }
    }, 1000);
}
run();
'
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Parando monitoramento..."
    pkill -f "node" 2>/dev/null
    echo "Status: Parado."
}

# --- CONTROLE ---
case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "Uso: $0 {start|stop}"; exit 1 ;;
esac
