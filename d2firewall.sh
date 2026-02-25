#!/bin/bash

# --- FUNÇÃO START ---
start() {
    echo "Conectando ao RPC da Polygon..."
    
    # Executando o código JavaScript puro sem as tags de citação
    node -e '
    const { ethers } = require("ethers");
    const provider = new ethers.JsonRpcProvider("https://polygon-rpc.com");
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    
    const aggregatorV3InterfaceABI = [
      "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)"
    ];

    const priceFeed = new ethers.Contract(btcUsdAddress, aggregatorV3InterfaceABI, provider);

    async function getBtcPrice() {
      try {
        const roundData = await priceFeed.latestRoundData();
        const price = Number(roundData.answer) / 10**8;
        
        console.log("------------------------------------------");
        console.log(`Preço Oficial Chainlink (BTC/USD): $${price}`);
        console.log("------------------------------------------");
      } catch (error) {
        console.error("Erro ao buscar o preço:", error);
      }
    }

    getBtcPrice();
    '
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Encerrando monitoramento..."
    pkill -f "node" 2>/dev/null
    echo "Status: Conexões finalizadas."
}

# --- CONTROLE DE EXECUÇÃO ---
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Uso: $0 {start|stop|restart}"
        exit 1
esac
