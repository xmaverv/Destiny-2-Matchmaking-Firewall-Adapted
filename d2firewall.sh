#!/bin/bash

# --- CONFIGURAÇÃO DE CAMINHO ---
# Altere para o caminho absoluto onde você instalou o ethers
PROJETO_DIR="/home/ubuntu/meu-projeto"

# --- FUNÇÃO START ---
start() {
    echo "Iniciando consulta ao Oráculo Chainlink (BTC/USD)..."
    
    # Entra na pasta do projeto para garantir o acesso ao node_modules
    cd "$PROJETO_DIR" || { echo "Erro: Pasta $PROJETO_DIR não encontrada"; exit 1; }

    node -e '
    const { ethers } = require("ethers");

    async function getBtcPrice() {
        // Conexão com RPC pública da Polygon 
        const provider = new ethers.JsonRpcProvider("https://polygon-bor-rpc.publicnode.com");
        
        // Endereço do contrato de Feed BTC/USD da Chainlink na Polygon [cite: 2]
        const btcUsdAddress = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
        
        // ABI contendo apenas a função que precisamos [cite: 3]
        const aggregatorV3InterfaceABI = [
          "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)"
        ];
        
        const priceFeed = new ethers.Contract(btcUsdAddress, aggregatorV3InterfaceABI, provider); [cite: 4]

        try {
            const roundData = await priceFeed.latestRoundData(); [cite: 4]
            // O valor retorna como BigInt com 8 casas decimais [cite: 5]
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
stop() {
    echo "Encerrando processo..."
    pkill -f "node" 2>/dev/null
    echo "Status: Parado."
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
