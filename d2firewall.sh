#!/bin/bash

# --- CONFIGURAÇÕES ---
# O script utiliza o Node.js para executar a lógica do ethers.js fornecida.

# --- FUNÇÃO START ---
# Conecta ao RPC da Polygon e busca o preço do BTC/USD via Chainlink
start() {
    echo "Conectando ao RPC da Polygon..." [cite: 1]
    
    node -e '
    const { ethers } = require("ethers");
    const provider = new ethers.JsonRpcProvider("https://polygon-rpc.com"); [cite: 1]
    const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f"; [cite: 2]
    
    const aggregatorV3InterfaceABI = [
      "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)"
    ]; [cite: 3]

    const priceFeed = new ethers.Contract(btcUsdAddress, aggregatorV3InterfaceABI, provider); [cite: 4]

    async function getBtcPrice() {
      try {
        const roundData = await priceFeed.latestRoundData(); [cite: 4]
        // Formatação: O valor vem com 8 casas decimais [cite: 5]
        const price = Number(roundData.answer) / 10**8; [cite: 6]
        
        console.log("------------------------------------------");
        console.log(`Preço Oficial Chainlink (BTC/USD): $${price}`); [cite: 6]
        console.log("------------------------------------------");
      } catch (error) {
        console.error("Erro ao buscar o preço:", error); [cite: 7]
      }
    }

    getBtcPrice();
    '
}

# --- FUNÇÃO STOP ---
# Finaliza a execução e limpa o terminal
stop() {
    echo "Encerrando monitoramento..."
    pkill -f "node" 2>/dev/null
    echo "Status: Conexões finalizadas."
}

# --- CONTROLE DE EXECUÇÃO (Baseado na estrutura d2firewall.sh) ---
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
