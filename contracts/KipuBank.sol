// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title KipuBank - Un smart contract seguro para depósitos y retiros de ETH
/// @author Matías Chacón
/// @notice Este contrato permite a los usuarios depositar y retirar ETH con límites definidos
/// @dev Se implemnetan buenas prácticas de seguridad y manejo de errores personalizados

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract KipuAccess is AccessControl {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    constructor(address admin) {
        require(admin != address(0), "Invalid admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
}

contract KipuBank is KipuAccess, ReentrancyGuard{
    using SafeERC20 for IERC20;
    
    // -----------------
    // VARIABLES
    // -----------------

    /// @notice Límite global de depósitos del banco (en wei)
    uint256 public bankCap;

    /// @notice Límite máximo por retiro (en wei)
    uint256 public withdrawLimit;

    /// @notice Saldo de ETH de cada usuario
    mapping(address => uint256) private vaults;

    /// @notice Contabilidad interna multi-token (user => token => amount)
    mapping(address => mapping(address => uint256)) private tokenVaults;

    /// @notice Cantidad total de depósitos realizados
    uint256 private totalDeposits;

    /// @notice Cantidad total de retiros realizados
    uint256 private totalWithdraws;

    /// @notice Precio actual de ETH en USD con 8 decimales (según Chainlink)
    uint256 public ethUsdPrice;

    /// @notice Instancia del feed de Chainlink
    AggregatorV3Interface public priceFeed;

    // -----------------
    // EVENTOS
    // -----------------
    
    /// @notice Evento emitido cuando un usario realiza un depósito
    event Deposit(address indexed user, address indexed token, uint256 amount);

    /// @notice Evento emitido cuando un usuario realiza un retiro
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    
    /// @notice Evento emitido cuando el límite global del banco se actualiza 
    event BankCapUpdated(uint256 newLimit);
    
    /// @notice Evento emitido cuando el límite de retiro se actualiza
    event WithdrawLimitUpdated(uint256 newLimit);

    /// @notice Evento emitido cuando el feed se actualiza
    event PriceFeedUpdated(address feed);

    /// @notice Evento emitido cuando el precio del ETH se actualiza
    event EthUsdPriceUpdated(uint256 newPrice);
    // -----------------
    // ERRORES PERSONALIZADOS
    // -----------------

    /// @notice Se lanza cuando el nuevo balance del contrato excede bankCap
    /// @param attempted Balance que se intentó alcanzar
    /// @param cap Límite máximo del banco
    error ExceedsBankCap(uint256 attempted, uint256 cap);

    /// @notice Se lanza cuando el retiro excede withdrawLimit
    /// @param attempted Cantidad solicitada para retirar
    /// @param limit Límite máximo por transacción
    error ExceedsWithdrawLimit(uint256 attempted, uint256 limit);

    /// @notice Se lanza cuando el usuario intenta retirar más ETH que lo que tiene disponible 
    /// @param available Saldo disponible del usuario
    /// @param requested Cantidad solicitada para retirar
    error InsufficientBalance(uint256 available, uint256 requested);

    /// @notice Se lanza si el depósito es 0
    error ZeroDeposit();

    error ZeroWithdrawal();

    /// @notice Se lanza si la transferencia nativa falla
    /// @param to Dirección a la que se intentó enviar ETH
    /// @param amount Cantidad que se intentó enviar
    error TransferFailed(address to, uint256 amount);

    /// @notice Se lanza si se detecta reentrancy
    /// @dev Usamos un bloqueo simple para prevenir ataques de reentrancy
    error ReentrancyAttack();

    // -----------------
    // MODIFICADORES
    // -----------------

    /// @notice Verifica que el depósito no supere el límite global del banco (bankCap)
    modifier underBankCap(uint256 amount) {
        if(address(this).balance + amount > bankCap) {
            revert ExceedsBankCap(address(this).balance + amount, bankCap);
        }
        _;
    }
    
    /// @notice Verifica que el retiro no supere el límite máximo por transacción
    modifier withinWithdrawLimit(uint256 amount) {
        if(amount > withdrawLimit) {
            revert ExceedsWithdrawLimit(amount, withdrawLimit);
        }
        _;
    }

    // -----------------
    // CONSTRUCTOR
    // -----------------

    /// @notice Constructor para inicializar los límites del banco
    /// @param _bankCap Límite global de depósitos (wei)
    /// @param _withdrawLimit Límite máximo por retiro (wei)
    /// @param admin address assigned DEFAULT_ADMIN_ROLE
    constructor(uint256 _bankCap, uint256 _withdrawLimit, address admin, address _priceFeed)
    KipuAccess(admin) {
        require(_priceFeed != address(0), "Invalid feed");
        bankCap = _bankCap;
        withdrawLimit = _withdrawLimit;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    // -----------------
    // ADMIN FUNCTIONS (only admin)
    // -----------------

    function setBankCap(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bankCap = newCap;
        emit BankCapUpdated(newCap);
    }

    function getBankCap() external view returns (uint256) {
        return bankCap;
    }

    function setWithdrawLimit(uint256 newLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawLimit = newLimit;
        emit WithdrawLimitUpdated(newLimit);
    }

    function getWithdrawLimit() external view returns (uint256) {
        return withdrawLimit;
    }

    function setPriceFeed(address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(feed != address(0), "Invalid feed");
        priceFeed = AggregatorV3Interface(feed);

        emit PriceFeedUpdated(feed);
    }

    // -----------------
    // FUNCIONES PÚBLICAS / EXTERNAS
    // -----------------

    /// @notice Deposita ETH en la bóveda del remitente
    /// @dev Usa el modificador underBankCap para validar el límite global y noReentrancy
    function deposit() external payable underBankCap(msg.value) nonReentrant {
        if(msg.value == 0) revert ZeroDeposit();

        vaults[msg.sender] += msg.value;
        totalDeposits++; // Incrementa el contador de depósitos

        emit Deposit(msg.sender, address(0), msg.value);
    }

    /// @notice Retira `amount` ETH de la bóveda del remitente
    /// @dev Sigue checks-effects-interactions y usa noReentrancy
    function withdraw(uint256 amount) external withinWithdrawLimit(amount) nonReentrant  {
        // --- CHECKS (validaciones) ---
        if (amount == 0) revert ZeroWithdrawal();

        uint256 bal = vaults[msg.sender];
        if (bal < amount) revert InsufficientBalance(bal, amount);

        // --- EFFECTS (actualizamos estado antes de la interacción externa) ---
        vaults[msg.sender] = bal - amount;
        totalWithdraws++;

        // --- INTERACTIONS (envío seguro usando call) ---
        (bool sent, ) = msg.sender.call{value: amount}("");
        if (!sent) revert TransferFailed(msg.sender, amount); // Revert si la transferencia falla

        emit Withdrawal(msg.sender, address(0), amount); // Emite el evento
    }

    /// @notice Deposita tokens ERC20 en la bóveda
    /// @param token Dirección del contrato del token
    /// @param amount Cantidad a depositar
    function depositToken(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroDeposit();
        if (amount == 0) revert ZeroDeposit();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        tokenVaults[msg.sender][token] += amount;

        emit Deposit(msg.sender, token, amount);
    }

    /// @notice Retira tokens ERC20 de la bóveda
    /// @param token dirrección del contrato del token 
    /// @param amount Cantidad a retirar
    function withdrawToken(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroWithdrawal();
        if (amount == 0) revert ZeroWithdrawal();

        uint256 bal = tokenVaults[msg.sender][token];
        if (bal < amount) revert InsufficientBalance(bal, amount);

        tokenVaults[msg.sender][token] = bal - amount;

        IERC20(token).safeTransfer(msg.sender, amount);
        totalWithdraws++;

        emit Withdrawal(msg.sender, token, amount);
    }

    /// @notice Consulta el balance de un token (address(0) para ETH)
    function getTokenBalance(address user, address token) external view returns (uint256) {
        if (token == address(0)) {
            return vaults[user];
        }
        return tokenVaults[user][token];
    }

    function convertToUsdcDecimals(address token, uint256 amount) public view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals(); // obtiene los decimales del token

        if (decimals > 6) {
            return amount / (10 ** (decimals - 6));
        } else {
            return amount * (10 ** (6 - decimals));
        }
    }

    // -----------------
    // ORÁCULO / PRICE
    // -----------------

    /// @notice Actualiza el precio de ETH/USD manualmente, solo el oráculo puede llamarla
    /// @param newPrice Nuevo valor del precio en formato ChainLink (8 decimales)
    function updateEthUsdPrice(uint256 newPrice) external onlyRole(ORACLE_ROLE) {
        require(newPrice > 0, "Invalid price");
        ethUsdPrice = newPrice;

        emit EthUsdPriceUpdated(newPrice);
    }

    /// @notice Lee el feed de Chainlink (si se configuró) y actualiza el precio (sólo ORACLE_ROLE)
    function updatePriceFromChainlink() external onlyRole(ORACLE_ROLE) nonReentrant  {
        require(address(priceFeed) != address(0), "Feed not set");
        (
            ,// roundID
            int256 latest,
            , // startedAt
            , // updatedAt
            // answeredInRound
        ) = priceFeed.latestRoundData();

        require(latest > 0, "Invalid feed data");
        ethUsdPrice = uint256(latest);

        emit EthUsdPriceUpdated(uint256(latest));
    }

    // -----------------
    // VIEWS
    // -----------------

    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }

    function getTotalWithdraws() external view returns (uint256) {
        return totalWithdraws;
    }

    /// @notice Devuelve el balance total retenido por el contrato
    function bankBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getLatestPrice() public view returns (int256) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint startedAt */,
            /* uint timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        return price; // Precio de 1 ETH en USD, con 8 decimales
    }
}