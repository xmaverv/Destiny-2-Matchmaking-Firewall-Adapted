#!/bin/bash

# --- FUNÇÃO START ---
start() {
    echo "Conectando ao RPC da Polygon..."
    
    node -e '
    const { ethers } = require("ethers");

    // Lista de RPCs alternativas caso a principal falhe
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
      // Tenta cada RPC da lista até uma funcionar
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
          return; // Sai da função se tiver sucesso
        } catch (err) {
          console.warn(`Falha na RPC ${url}, tentando a próxima...`);
        }
      }
      console.error("Todas as RPCs falharam. Verifique sua conexão.");
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
