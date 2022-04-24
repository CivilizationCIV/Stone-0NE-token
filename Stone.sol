//SPDX-License-Identifier:MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";

/**
 * @title Stone ERC-20 token Contract
 */

contract Stone is Ownable, ERC20, Pausable {
    using LowGasSafeMath for uint256;
    using FullMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Event emitted when tax rate changes
    event taxChanged(uint256 _taxRate);

    /// @notice Event emitted when bot tax rate changes
    event botTaxChanged(uint256 _botTaxRate);

    /// @notice Event emitted when add or remove size free account
    event sizeFreeChanged(address _sizeFreeAccount);

    /// @notice Event emitted when add or remove tax free account
    event taxFreeChanged(address _taxFreeAccount);

    /// @notice Event emitted when add or remove blacklistWallet
    event blacklistWalletChanged(address _blacklistWalletAccount);

    /// @notice Event emitted when add or remove botWallet
    event botWalletChanged(address _botWalletAccount);

    /// @notice Event emitted when burn address changes
    event burnAddressChanged(address _newBurnAddress);

    /// @notice Event emitted when transfer stone token with fee
    event transferWithTax(
        address _sender,
        address _recipient,
        uint256 amount,
        uint256 _burnAmount
    );

    address public burnWallet = 0xd26Cc7C8D96F6Ca5291758d266447f6879A66E16;
    uint256 internal constant maxSupply = 10**33;
    mapping(address => bool) public taxFree;
    mapping(address => bool) public sizeFree;
    mapping(address => bool) public blacklistWallet;
    mapping(address => bool) public botWallet;
    uint256 public taxRate = 9999; // basis points, 10000 is 100%; start high for anti-sniping
    uint256 public botTaxRate = 900; // 9% bot tax

    /**
     * @dev Constructor
     */
    constructor() ERC20("Stone", "0NE") {
        _mint(_msgSender(), 2 * 10**32);
        taxFree[_msgSender()] = true;
        sizeFree[_msgSender()] = true;
    }

    /**
     * @dev External function to set tax Rate
     * @param _taxRate New tax Rate in basis points
     */
    function setTaxRate(uint256 _taxRate) external onlyOwner {
        require(_taxRate >= 0, "TaxRate above zero");
        require(_taxRate <= 10000, "TaxRate below max");

        taxRate = _taxRate;
        emit taxChanged(_taxRate);
    }

    /**
     * @dev External function to set bot tax Rate
     * @param _botTaxRate New tax Rate in basis points
     */
    function setBotRate(uint256 _botTaxRate) external onlyOwner {
        require(_botTaxRate >= 0, "TaxRate above zero");
        require(_botTaxRate <= 10000, "TaxRate below max");

        botTaxRate = _botTaxRate;
        emit botTaxChanged(_botTaxRate);
    }

    /**
     * @dev Add or remove tax free accounts
     * @param _account target address to set or remove from the tax free account list
     */
    function setTaxFree(address _account) external onlyOwner {
        if (taxFree[_account]) {
            delete taxFree[_account];
        } else {
            taxFree[_account] = true;
        }

        emit taxFreeChanged(_account);
    }

    /**
     * @dev Add or remove size free accounts
     * @param _account target address to set or remove from the size free account list
     */
    function setSizeFree(address _account) external onlyOwner {
        if (sizeFree[_account]) {
            delete sizeFree[_account];
        } else {
            sizeFree[_account] = true;
        }

        emit sizeFreeChanged(_account);
    }

    /**
     * @dev Add or remove blacklist wallet accounts
     * @param _account target address to set or remove from the blacklist account list
     */
    function setBlacklistWallet(address _account) external onlyOwner {
        if (blacklistWallet[_account]) {
            delete blacklistWallet[_account];
        } else {
            blacklistWallet[_account] = true;
        }

        emit blacklistWalletChanged(_account);
    }

    /**
     * @dev Add or remove bot wallet accounts
     * @param _account target address to set or remove from the bot account list
     */
    function setBotWallet(address _account) external onlyOwner {
        if (botWallet[_account]) {
            delete botWallet[_account];
        } else {
            botWallet[_account] = true;
        }

        emit botWalletChanged(_account);
    }

    /**
     * @dev Custom transfer function
     * @param sender Sender address
     * @param recipient Recipient address
     * @param amount Amount to transfer
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override whenNotPaused {
        require(balanceOf(sender) >= amount, "Not enough tokens");

        //black listed wallets are not welcome, sorry!
        require(
            !blacklistWallet[sender] && !blacklistWallet[recipient],
            "Not welcome!"
        );

        if (!sizeFree[recipient]) {
            require(
                balanceOf(recipient).add(amount) <= 3 * 10**31,
                "Transfer exceeds max wallet"
            ); //3% max
        }

        //bots pay higher tax, sorry!
        uint256 _taxApplied = (botWallet[sender] || botWallet[recipient])
            ? botTaxRate
            : taxRate;

        //Divide by 20000 for the 50-50% split
        uint256 _burnAmount = (taxFree[sender] || taxFree[recipient])
            ? 0
            : FullMath.mulDiv(amount, _taxApplied, 20000);

        if (_burnAmount > 0) {
            _burn(sender, _burnAmount); //burn Stone
            ERC20._transfer(sender, burnWallet, _burnAmount); //burn Civ to dedicated wallet
        }

        ERC20._transfer(sender, recipient, amount - (_burnAmount.mul(2))); //then transfer

        emit transferWithTax(sender, recipient, amount, _burnAmount);
    }

    /**
     * @dev Set burn address
     * @param _burnAddress New burn address
     */
    function setBurnAddress(address _burnAddress) external onlyOwner {
        burnWallet = _burnAddress;
        emit burnAddressChanged(burnWallet);
    }

    /**
     * @dev Mint new stone tokens
     * @param count Amount to mint
     */
    function mintToken(uint256 count) external onlyOwner {
        require(totalSupply() + count <= maxSupply, "Mint above maxSupply");
        _mint(_msgSender(), count);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* Just in case anyone sends tokens by accident to this contract */

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "STE");
    }

    function withdrawETH() external payable onlyOwner {
        safeTransferETH(_msgSender(), address(this).balance);
    }

    function withdrawERC20(IERC20 _tokenContract) external onlyOwner {
        _tokenContract.safeTransfer(
            _msgSender(),
            _tokenContract.balanceOf(address(this))
        );
    }

    /**
     * @dev allow the contract to receive ETH
     * without payable fallback and receive, it would fail
     */
    fallback() external payable {}

    receive() external payable {}
}
