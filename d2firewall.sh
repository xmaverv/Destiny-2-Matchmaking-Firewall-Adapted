#!/bin/bash

# --- FUNÇÃO START ---
start() {
    echo "Conectando ao RPC da Polygon..."
    
    # Define o caminho das bibliotecas para o Node encontrar o ethers
    export NODE_PATH=$(pwd)/node_modules:$(npm root -g)

    node -e '
    const { ethers } = require("ethers");

    const rpcUrls = [
      "https://polygon-bor-rpc.publicnode.com",
      "https://1rpc.io/matic",
      "https://polygon.llamarpc.com"
    ];

    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
    const aggregatorV3InterfaceABI = [
      "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)"
    ];

    async function getBtcPrice() {
      for (const url of rpcUrls) {
        try {
          const provider = new ethers.JsonRpcProvider(url);
          const priceFeed = new ethers.Contract(btcUsdAddress, aggregatorV3InterfaceABI, provider);
          
          const roundData = await priceFeed.latestRoundData();
          const price = Number(roundData.answer) / 1e8;
          
          console.log("------------------------------------------");
          console.log("Conectado com sucesso!");
          console.log("Preço Oficial Chainlink (BTC/USD): $" + price);
          console.log("------------------------------------------");
          process.exit(0);
        } catch (err) {
          // Tenta a próxima RPC silenciosamente
        }
      }
      console.error("Erro: Todas as conexões RPC falharam.");
      process.exit(1);
    }

    getBtcPrice();
    '
}

# --- FUNÇÃO STOP ---
stop() {
    echo "Encerrando..."
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
