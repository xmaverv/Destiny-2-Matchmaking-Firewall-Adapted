#!/bin/bash

# --- FUNÇÃO START ---
start() {
    echo "Conectando ao RPC da Polygon..."
    
    # O comando abaixo usa o diretório atual para procurar os node_modules
    # Isso resolve o problema do "Cannot find module ethers"
    export NODE_PATH=$(pwd)/node_modules

    node -e '
    const { ethers } = require("ethers"); 

    const rpcUrls = [
      "https://polygon-bor-rpc.publicnode.com",
      "https://1rpc.io/matic",
      "https://polygon.llamarpc.com"
    ]; 

    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f"; [cite: 2]
    const aggregatorV3InterfaceABI = [
      "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)"
    ]; [cite: 3]

    async function getBtcPrice() {
      for (const url of rpcUrls) {
        try {
          const provider = new ethers.JsonRpcProvider(url); 
          const priceFeed = new ethers.Contract(btcUsdAddress, aggregatorV3InterfaceABI, provider); [cite: 4]
          
          const roundData = await priceFeed.latestRoundData(); [cite: 4]
          const price = Number(roundData.answer) / 10**8; [cite: 5, 6]
          
          console.log("------------------------------------------");
          console.log(`Conectado via: ${url}`);
          console.log(`Preço Oficial Chainlink (BTC/USD): $${price}`); [cite: 6]
          console.log("------------------------------------------");
          return;
        } catch (err) {
          continue;
        }
      }
      console.error("Erro: Não foi possível conectar a nenhuma RPC.");
    }

    getBtcPrice();
    '
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Encerrando processo..."
    pkill -f "node" 2>/dev/null
    echo "Status: Parado."
}

# --- CONTROLE ---
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    *)
        echo "Uso: $0 {start|stop}"
        exit 1
esac
