# KipuBank V2

KipuBank V2 es la evolución del contrato original, transformándolo en una solución de grado producción con soporte multi-token, control de acceso basado en roles, integración con oráculos de Chainlink y arquitectura modular escalable.

## Mejoras Principales

### 1. **Control de Acceso Basado en Roles**
- Implementación de `AccessControl` de OpenZeppelin
- Rol `DEFAULT_ADMIN_ROLE` para gestión de parámetros del banco
- Rol `ORACLE_ROLE` para actualización de precios
- Arquitectura modular con contrato abstracto `KipuAccess`

### 2. **Soporte Multi-Token**
- Depósitos y retiros de tokens ERC-20 además de ETH
- Contabilidad interna mediante mappings anidados `tokenVaults[user][token]`
- Uso de `address(0)` para representar ETH nativo
- Implementación de `SafeERC20` para transferencias seguras

### 3. **Integración con Oráculos Chainlink**
- Feed de precio ETH/USD en tiempo real
- Función `updatePriceFromChainlink()` para actualización automática
- Soporte para actualización manual con `updateEthUsdPrice()`
- Conversión de valores para control de límites en USD

### 4. **Gestión de Decimales**
- Función `convertToUsdcDecimals()` para normalización de tokens
- Manejo de tokens con diferentes precisiones (6, 8, 18 decimales)
- Soporte para USDC como unidad de referencia

### 5. **Seguridad Mejorada**
- `ReentrancyGuard` de OpenZeppelin en todas las funciones críticas
- Patrón Checks-Effects-Interactions estrictamente aplicado
- Errores personalizados para optimización de gas
- Validaciones exhaustivas en todos los flujos

### 6. **Administración Dinámica**
- Funciones `setBankCap()` y `setWithdrawLimit()` para ajustar límites
- `setPriceFeed()` para actualizar el oráculo
- Control granular mediante roles

# Clonar el repositorio
```bash
git clone https://github.com/Maty910/KipuBankV2.git
cd KipuBankV2
```

## Diferencias vs V1

| Característica | V1 | V2 |
|----------------|----|----|
| Tokens soportados | Solo ETH | ETH + ERC-20 |
| Control de acceso | No | Roles con AccessControl |
| Oráculo de precios | No | Chainlink Price Feed |
| Límites dinámicos | Inmutables | Configurables por admin |
| Decimales | No aplica | Conversión multi-token |
| Arquitectura | Monolítica | Modular (herencia) |

## Decisiones de Diseño

### Por qué AccessControl en lugar de Ownable
- **Escalabilidad**: Permite múltiples administradores con diferentes permisos
- **Separación de responsabilidades**: El oráculo no necesita ser admin
- **Flexibilidad**: Facilita agregar nuevos roles sin refactorizar

### Por qué mappings anidados para tokens
- **Gas eficiente**: Un solo storage slot por balance
- **Escalabilidad**: Soporta infinitos tokens sin cambios en el contrato
- **Claridad**: `tokenVaults[user][token]` es más legible que alternativas

### Trade-offs considerados
- **Chainlink vs Manual**: Se mantienen ambas opciones para flexibilidad en diferentes redes
- **Inmutabilidad del PriceFeed**: Se permite cambiar la dirección para casos de actualización del protocolo
- **ReentrancyGuard en views**: Solo en funciones que interactúan con contratos externos

## Estructura del Proyecto

```
KipuBankV2/
├── src/
│   └── KipuBank.sol          # Contrato principal
└── README.md
```

## Despliegue

### Parámetros del Constructor

```solidity
constructor(
    uint256 _bankCap,        // Límite global (wei)
    uint256 _withdrawLimit,  // Límite por retiro (wei)
    address admin,           // Dirección con DEFAULT_ADMIN_ROLE
    address _priceFeed       // Chainlink Price Feed (ETH/USD)
)
```

### Ejemplo en Sepolia

```javascript
_bankCap: 10000000000000000000        // 10 ETH
_withdrawLimit: 1000000000000000000   // 1 ETH
admin: 0x84f...e28ac                  // Tu wallet
_priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306  // Chainlink ETH/USD Sepolia
```

### Compilación

- Solidity: `0.8.30`
- Optimización: Habilitada (200 runs)
- EVM Version: Paris

## Contrato Desplegado

**Red:** Sepolia Testnet  
**Address:** `0xc4Da572710D0361765aC3719C6aE7a317646e05f`  
**Etherscan:** [Ver código verificado](https://sepolia.etherscan.io/address/0xc4Da572710D0361765aC3719C6aE7a317646e05f#code)

## Funcionalidades Principales

### Para Usuarios
- `deposit()` - Depositar ETH
- `depositToken(address token, uint256 amount)` - Depositar ERC-20
- `withdraw(uint256 amount)` - Retirar ETH
- `withdrawToken(address token, uint256 amount)` - Retirar ERC-20
- `getTokenBalance(address user, address token)` - Consultar saldo

### Para Administradores
- `setBankCap(uint256 newCap)` - Ajustar límite global
- `setWithdrawLimit(uint256 newLimit)` - Ajustar límite de retiro
- `setPriceFeed(address feed)` - Cambiar oráculo
- `grantRole(bytes32 role, address account)` - Asignar roles

### Para Oráculos
- `updateEthUsdPrice(uint256 newPrice)` - Actualizar precio manualmente
- `updatePriceFromChainlink()` - Actualizar desde Chainlink

## Patrones de Seguridad

-  **Checks-Effects-Interactions** - Orden correcto en todas las funciones
-  **ReentrancyGuard** - Protección contra ataques de reentrancy
-  **SafeERC20** - Transferencias seguras de tokens
-  **Access Control** - Restricción de funciones críticas
-  **Custom Errors** - Eficiencia en gas y claridad
-  **Input Validation** - Validaciones exhaustivas con `require`

## Testing

### Casos de Prueba Implementados
- Depósitos y retiros de ETH
- Depósitos y retiros multi-token
- Validación de límites (bankCap, withdrawLimit)
- Control de acceso por roles
- Actualización de precios desde oráculo
- Conversión de decimales entre tokens

## Autor

**Matías Chacón**  
Proyecto Final Módulo 3

## Licencia

MIT License - Ver contrato para detalles

---

**Versión anterior:** [KipuBank V1](https://github.com/Maty910/kipu-bank)



