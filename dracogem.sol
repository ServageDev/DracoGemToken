// SPDX-License-Identifier: MIT

//OPENZEPPELIN IMPORTS
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

//UNISWAP IMPORTS
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

pragma solidity 0.8.23;

contract DracoGem is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => uint256) private _reflectionOwned;
    mapping (address => uint256) private _tokensOwned;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _isExcludedFromAutoLiquidity;

    address[] private _excluded;
    address public _marketingWallet;
    address public _burnFeeReceiver;
    address public _teamWallet;
    address public _developementWallet;
    address public _stakingWallet;
    address public _uniswapV2Pair;
    string private _name   = "DracoGem Token";
    string private _symbol = "DG";
    uint8 private  _decimals = 18;
    uint256 private constant MAX = ~uint256(0);
    uint256 private _totalSupply = 900e9 * 10**_decimals;
    uint256 private _rTotal = (MAX - (MAX % _totalSupply));
    uint256 private _tFeeTotal;

    uint256 public _liquidityFee = 14; 
    uint256 public _taxFee = 1;

    uint256 public _percentageOfLiquidityForMarketingFee = 25;
    uint256 public _percentageOfLiquidityForBurnFee = 20;
    uint256 public _percentageOfLiquidityForTeamFee = 15;
    uint256 public _percentageOfLiquidityForDevFee  = 5;
    uint256 public _percentageOfLiquidityForStakingFee = 5;

    uint256 public  _maxTxAmount = 18e9 * 10**_decimals;
    uint256 private _minTokenBalance = 10000 * 10**_decimals;

    bool public _autoLiquifyAndDistributeEnabled = true;
    bool _inAutoLiquifyAndDistribute;
    IUniswapV2Router02 public _uniswapV2Router;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event AutoLiquifyAndDistributeEnabledUpdated(bool enabled);
    event AutoLiquifyAndDistribute(uint256 tokensSwapped, uint256 bnbReceived, uint256 tokensIntoLiqudity);
    event MarketingFeeSent(address to, uint256 bnbSent);
    event BurnFeeSent(address to, uint256 bnbSent);
    event TeamFeeSent(address to, uint256 bnbSent);
    event DevFeeSent(address to, uint256 bnbSent);
    event stakingFeeSent(address to, uint256 bnbSent);
    
    modifier stopALD {
        _inAutoLiquifyAndDistribute = true;
        _;
        _inAutoLiquifyAndDistribute = false;
    }
    
    constructor (
        address contractOwner,
        address marketingWallet, 
        address teamWallet,
        address developementWallet,
        address stakingWallet) Ownable(contractOwner) {

        // set wallet addresses minus burn address which is hardcoded in contract.
        _marketingWallet = marketingWallet;
        _burnFeeReceiver = contractOwner;
        _teamWallet = teamWallet;
        _developementWallet  = developementWallet;
        _stakingWallet = stakingWallet;
        _reflectionOwned[contractOwner] = _rTotal;
        
        // PancakeRouterV2
        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // Pancakeswap MAINNET BSC
        _uniswapV2Router = uniswapV2Router;
        _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        
        // exclude system contracts
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_marketingWallet] = true;
        _isExcludedFromFee[_burnFeeReceiver] = true;
        _isExcludedFromFee[_teamWallet] = true;
        _isExcludedFromFee[_developementWallet]  = true;
        _isExcludedFromFee[_stakingWallet] = true;

        _isExcludedFromAutoLiquidity[_uniswapV2Pair] = true;
        _isExcludedFromAutoLiquidity[address(_uniswapV2Router)] = true;
        
        emit Transfer(address(0), contractOwner, _totalSupply);
    }

    /// @notice makes contract recievable
    receive() external payable {}
    
    /// @notice checks for amount to be less than contract balance and transfers amount to payee
    function withdraw(uint256 amount, address payee) external onlyOwner {
        require(amount < address(this).balance);
        payable(payee).transfer(amount);
    }

    /** 
        @notice include address passed in in the reward
        @param account to include in reward
     */
    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is already excluded");

        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tokensOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    /**
        @notice set Marketing fee wallet to address provided
        @param marketingWallet to set as wallet
     */
    function setMarketingFeeWallet(address marketingWallet) external onlyOwner {
        _marketingWallet = marketingWallet;
    }
    
    /**
        @notice set Team fee wallet to address provided
        @param teamWallet to set as wallet
     */
    function setTeamWallet(address teamWallet) external onlyOwner {
        _teamWallet = teamWallet;
    }

    /**
        @notice set Dev fee wallet to address provided
        @param developementWallet to set as wallet
     */
    function setDevWallet(address developementWallet) external onlyOwner {
        _developementWallet = developementWallet;
    }
    
    /**
        @notice set community and referral fee wallet to address provided
        @param stakingWallet to set as wallet
     */
    function setStakingWallet(address stakingWallet) external onlyOwner {
        _stakingWallet = stakingWallet;    
    }
    
    /**
        @notice set account to either be excluded or not excluded from fee dependant on bool(e) passed in
        @param account to be excluded or not excluded
        @param e boolean flag for address being set
     */
    function setExcludedFromFee(address account, bool e) external onlyOwner {
        _isExcludedFromFee[account] = e;
    }

    /**
        @notice set liquidity fee percent i.e. the percentage being split between the sub fees
        @param liquidityFee percent to be set in uint256
     */
    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        _liquidityFee = liquidityFee;
    }

    /**
        @notice set percentage of liquidity fee for marketing fee wallet 
        @param marketingFee percent to be set in uint256
     */
    function setPercentageOfLiquidityForMarketingFee(uint256 marketingFee) external onlyOwner {
        _percentageOfLiquidityForMarketingFee = marketingFee;
    }
    
    /**
        @notice set percentage of liquidity fee for team fee wallet 
        @param teamFee percent to be set in uint256
     */
    function setPercentageOfLiquidityForTeamFee(uint256 teamFee) external onlyOwner {
        _percentageOfLiquidityForTeamFee = teamFee;
    }

    /**
        @notice set percentage of liquidity fee for dev fee wallet 
        @param devFee percent to be set in uint256
     */
    function setPercentageOfLiquidityForDevFee(uint256 devFee) external onlyOwner {
        _percentageOfLiquidityForDevFee = devFee;
    }

    /** 
        @notice set max transaction amount
        @param maxTxAmount to set in uint256
     */
    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        _maxTxAmount = maxTxAmount;
    }

    /**
        @notice set uniswapV2Router address
        @param r address for router
     */
    function setUniswapRouter(address r) external onlyOwner {
        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(r);
        _uniswapV2Router = uniswapV2Router;
    }

    /**
        @notice set uniswapV2Pair address 
        @param p address for pair
     */
    function setUniswapPair(address p) external onlyOwner {
        _uniswapV2Pair = p;
    }

    /**
        @notice set address(a) to be either excluded or included in auto liquidity based on bool(b) passed in
        @param a address to be excluded or not 
        @param b boolean flag for address passed in
     */
    function setExcludedFromAutoLiquidity(address a, bool b) external onlyOwner {
        _isExcludedFromAutoLiquidity[a] = b;
    }

    /**
        @notice transfer amount to recipient
        @param recipient address of receiver of amount
        @param amount to be sent to recipient address
        @return bool true on successful completion
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
        @notice approve spender to spend amount on _msgSender
        @param spender address to be approved for amount
        @param amount to be approved for spender to spend
        @return bool true on successful completion
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
        @notice transfer amount from sender to recipient
        @param sender address sending amount
        @param recipient address to receive amount
        @param amount in uint256 value going from sender to recipient
        @return bool true on successful completion
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
    }

    /**
        @notice increase allowance of spender by addedValue
        @param spender address to have allowance increased by specific amount
        @param addedValue value to be added to spenders allowance
        @return bool true on successful completion
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
        @notice decrease allowance of spender by subtractedValue
        @param spender address to have allowance decreased by specific amount
        @param subtractedValue value to be subtracted from spenders allowance
        @return bool true on successful completion
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }

    /**
        @notice exclude account from reward
        @param account address to be excluded from reward
     */
    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");

        if (_reflectionOwned[account] > 0) {
            _tokensOwned[account] = tokenFromReflection(_reflectionOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    /**
        @notice set autoLiquifyAndDistribute to either enabled or disabled dependant on the bool(e) passed in
        @param e boolean flag to set autoLiquifyAndDistributeEnabled variable to
     */
    function setAutoLiquifyAndDistributeEnabled(bool e) public onlyOwner {
        _autoLiquifyAndDistributeEnabled = e;
        emit AutoLiquifyAndDistributeEnabledUpdated(e);
    }

    /**
        @notice see if account is excluded from fee 
        @param account address to check
        @return bool true if IS excluded and false if IS NOT excluded
     */
    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    /**
        @notice see if account is excluded from reward
        @param account address to check
        @return bool true if IS excluded and false if IS NOT excluded
     */
    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    /**
        @notice returns total fees 
        @return uint256 value of total fees 
     */
    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    /**
        @notice calculate reflection totals with or without transfer fees based on a total amount value passed in
        @param tAmount uin256 value total token value with which to retrieve reflection information from
        @param deductTransferFee bool flag to indicate whether to include transferFee or not
        @return uint256 value of reflection amount
    */
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _totalSupply, "Amount must be less than supply");
        (, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        uint256 currentRate = _getRate();

        if (!deductTransferFee) {
            (uint256 rAmount,,) = _getRValues(tAmount, tFee, tLiquidity, currentRate);
            return rAmount;

        } else {
            (, uint256 rTransferAmount,) = _getRValues(tAmount, tFee, tLiquidity, currentRate);
            return rTransferAmount;
        }
    }

    /**
        @notice calculate the amount of tokens held from a reflection based on current rate
        @param rAmount uint256 amount of reflections
        @return uint256 value of token
    */
    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");

        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    /**
        @notice return allowance of spender for owner
        @param owner address of wallet being spent on
        @param spender address of wallet spending 
        @return uint256 value of allowance for spender on owner wallet
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
        @notice get the name of the token 
        @return string of name
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
        @notice get token symbol
        @return string symbol for the token 
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
        @notice get token decimal count
        @return uint8 decimal count for the token 
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
        @notice get total supply
        @return uint256 total supply
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
        @notice get balance of specific account
        @param account address to get balance of
        @return the balance of tokens held by the account requested in uint256
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tokensOwned[account];
        return tokenFromReflection(_reflectionOwned[account]);
    }

    /*
     * calculate reflection fee and update totals
     */
    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    /**
        @notice calcs and takes the transaction fee
        @param to address to take action on
        @param tAmount taxed transfer amount
        @param currentRate current ratio of rTotal/tTotal
     */
    function takeTransactionFee(address to, uint256 tAmount, uint256 currentRate) private {
        if (tAmount <= 0) { return; }

        uint256 rAmount = tAmount.mul(currentRate);
        _reflectionOwned[to] = _reflectionOwned[to].add(rAmount);
        if (_isExcluded[to]) {
            _tokensOwned[to] = _tokensOwned[to].add(tAmount);
        }
    }

    /**
        @notice appove spender for amount on owner
        @param owner address of wallet approving spender for amount
        @param spender getting approved by wallet owner for amount
        @param amount in uint256 getting approved by owner for spender to spend
     */
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
        @notice transfer FROM TO for AMOUNT.
        @dev commenting done throughout function. 
        @param from address initiating transfer
        @param to address recieving transfer
        @param amount uint256 amount being transferred
    */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (from != owner() && to != owner()) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }

        /*
            - autoLiquifyAndDistribute will be initiated when token balance of this contract
            has accumulated enough over the minimum number of tokens required.
            - don't get caught in a circular liquidity event.
            - don't autoLiquifyAndDistribute if sender is uniswap pair.
        */
        uint256 contractTokenBalance = balanceOf(address(this));
        
        // check that there are more or equal tokens in contract than max transaction amount 
        // if true set to max transaction amount
        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }
        
        // boolean condition for SaL to occur
        // must meet below + not be in SaL + not from address not be excluded from SaL + SaL must be enabled
        bool isOverMinTokenBalance = contractTokenBalance >= _minTokenBalance;
        if (
            isOverMinTokenBalance &&
            !_inAutoLiquifyAndDistribute &&
            !_isExcludedFromAutoLiquidity[from] &&
            _autoLiquifyAndDistributeEnabled
        ) {
            autoLiquifyAndDistribute(contractTokenBalance);
        }

        // dont take fee if from or to is excluded 
        bool takeFee = true;
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }
        _tokenTransfer(from, to, amount, takeFee);
    }

    /** 
        @notice primary auto-liquify function. Also responsible for distributing fee collecitons to designated wallets. Only happens when holders sell and stopALD conditionals are met. 
        @dev Commented throughout. Read for explanation.
        @param contractTokenBalance uint256 amount of tokens currently held by contract to be used for sending to LP Pool 
    */
    function autoLiquifyAndDistribute(uint256 contractTokenBalance) private stopALD {
        // split contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        /*
            capture the contract's current BNB balance.
            this is so that we can capture exactly the amount of BNB that
            the swap creates, and not make the liquidity event include any BNB
            that has been manually sent to the contract.
        */
        uint256 initialBalance = address(this).balance;

        // swap tokens for BNB
        swapTokensForBnb(half);
        
        /*
            This is the amount of BNB on the contract that 
            we just swapped with subtracted from the 
            captured amount before the swap.
        */
        uint256 newBalance = address(this).balance.sub(initialBalance);
        
        // take marketing fee
        uint256 marketingFee = newBalance.mul(_percentageOfLiquidityForMarketingFee).div(100);
        
        // take burn fee 
        uint256 burnFee = newBalance.mul(_percentageOfLiquidityForBurnFee).div(100);
        
        // take team fee
        uint256 teamFee = newBalance.mul(_percentageOfLiquidityForTeamFee).div(100);

        // take dev fee
        uint256 devFee = newBalance.mul(_percentageOfLiquidityForDevFee).div(100);
        
        // take community and referral fees
        uint256 stakingFee = newBalance.mul(_percentageOfLiquidityForStakingFee).div(100);
        
        // add fees together to get total fees to sub
        uint256 txFees = marketingFee.add(teamFee).add(devFee).add(stakingFee).add(burnFee);
        
        // sub fees to get bnbForLiquidity
        uint256 bnbForLiquidity = newBalance.sub(txFees);
        
        // pay marketing wallet and emit event
        if (marketingFee > 0) {
            payable(_marketingWallet).transfer(marketingFee);
            emit MarketingFeeSent(_marketingWallet, marketingFee);
        }
        
        // pay team wallet and emit event
        if (teamFee > 0) {
            payable(_teamWallet).transfer(teamFee);
            emit TeamFeeSent(_teamWallet, teamFee);
        }

        // pay dev wallet and emit event
        if (devFee > 0) {
            payable(_developementWallet).transfer(devFee);
            emit DevFeeSent(_developementWallet, devFee);
        }
        
        // pay community and referral wallet and emit event
        if (stakingFee > 0) {
            payable(_stakingWallet).transfer(stakingFee);
            emit stakingFeeSent(_stakingWallet, stakingFee);
        }
        
        // pay burn fee to be burned manually
        if (burnFee > 0) {
            payable(_burnFeeReceiver).transfer(burnFee);
            emit BurnFeeSent(_burnFeeReceiver, burnFee);
        }
        
        /*
            add liquidity to pancakeswap with the half 
            that was swapped into tokens,
            and the remaining bnb after distribution.
        */
        addLiquidity(otherHalf, bnbForLiquidity);
        
        emit AutoLiquifyAndDistribute(half, bnbForLiquidity, otherHalf);
    }
    
    /**
        @notice swap tokenAmount for bnb
        @param tokenAmount uint256 amount to swap
    */
    function swapTokensForBnb(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router.WETH();

        _approve(address(this), address(_uniswapV2Router), tokenAmount);

        /* 
            call the pancakswapV2router contract for swapping tokens 
            for BNB with support for tokens with fees.
        */
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of BNB
            path,
            address(this),
            block.timestamp
        );
    }

    /**
        @notice add liquidity in amounts passed in using uniswapV2Router addLiquidityETH function
        @param tokenAmount uint256 amount of tokens to be added to liquidity pool
        @param bnbAmount uint256 amount of bnb to be added to liquidity pool
     */
    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(_uniswapV2Router), tokenAmount);

        // add the liquidity
        _uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    /**
        @notice token transfer function used in _transfer
        @param sender address initiating transaction
        @param recipient address recieving the amount sent
        @param amount uint256 value of asset being transacted with
        @param takeFee bool flag indicating whether to take fees or not.
     */
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        uint256 previousTaxFee = _taxFee;
        uint256 previousLiquidityFee = _liquidityFee;
        
        // if takeFee is false set fees to 0
        if (!takeFee) {
            _taxFee = 0;
            _liquidityFee = 0;
        }
        
        // sender is excluded 
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        // recipient is excluded
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        // neither are excluded 
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        // both are excluded
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        // default
        } else {
            _transferStandard(sender, recipient, amount);
        }
        // reset fees if bool was met above
        if (!takeFee) {
            _taxFee = previousTaxFee;
            _liquidityFee = previousLiquidityFee;
        }
    }

    /**
        @notice standard transfer function called internally when neither sender nor recipient is excluded from fee
        @param sender address initiating transaction
        @param recipient address recieving asset transacted on
        @param tAmount uint256 value of amount being sent 
     */
    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, currentRate);

        _reflectionOwned[sender] = _reflectionOwned[sender].sub(rAmount);
        _reflectionOwned[recipient] = _reflectionOwned[recipient].add(rTransferAmount);

        takeTransactionFee(address(this), tLiquidity, currentRate);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
        @notice transfer function called internally when both sender and recipient is excluded from fee
        @param sender address initiating transaction
        @param recipient address recieving asset transacted on
        @param tAmount uint256 value of amount being sent 
     */
    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, currentRate);

        _tokensOwned[sender] = _tokensOwned[sender].sub(tAmount);
        _reflectionOwned[sender] = _reflectionOwned[sender].sub(rAmount);
        _tokensOwned[recipient] = _tokensOwned[recipient].add(tTransferAmount);
        _reflectionOwned[recipient] = _reflectionOwned[recipient].add(rTransferAmount);

        takeTransactionFee(address(this), tLiquidity, currentRate);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
        @notice transfer function called internally when only recipient is excluded from fee
        @param sender address initiating transaction
        @param recipient address recieving asset transacted on
        @param tAmount uint256 value of amount being sent 
     */
    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, currentRate);

        _reflectionOwned[sender] = _reflectionOwned[sender].sub(rAmount);
        _tokensOwned[recipient] = _tokensOwned[recipient].add(tTransferAmount);
        _reflectionOwned[recipient] = _reflectionOwned[recipient].add(rTransferAmount);

        takeTransactionFee(address(this), tLiquidity, currentRate);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
        @notice transfer function called internally when only sender is excluded from fee
        @param sender address initiating transaction
        @param recipient address recieving asset transacted on
        @param tAmount uint256 value of amount being sent 
     */
    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, currentRate);

        _tokensOwned[sender] = _tokensOwned[sender].sub(tAmount);
        _reflectionOwned[sender] = _reflectionOwned[sender].sub(rAmount);
        _reflectionOwned[recipient] = _reflectionOwned[recipient].add(rTransferAmount);
        
        takeTransactionFee(address(this), tLiquidity, currentRate);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
        @notice calcs fee into .00 format
        @param amount uint256 amount to calculate fee on
        @param fee uint256 fee to calculate onto amount
        @return uint256 value of amount with fee calculated into it
     */
    function calculateFee(uint256 amount, uint256 fee) private pure returns (uint256) {
        return amount.mul(fee).div(100);
    }

    /**
        @notice get rValues or the reflection values based on current rate and supplied values
        @param tAmount uint256 token amount to get value off of
        @param tFee uint256 token fee amount
        @param tLiquidity uint256 token liquidity fee 
        @param currentRate uint256 current rate of r/t
        @return rAmount uint256 
        @return rTransferAmount uint256 
        @return rFee uint256 
     */
    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount    = tAmount.mul(currentRate);
        uint256 rFee       = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee);
        rTransferAmount = rTransferAmount.sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    /**
        @notice get the current supply
        @return rSupply uint256
        @return tSupply uint256
     */
    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _totalSupply;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_reflectionOwned[_excluded[i]] > rSupply || _tokensOwned[_excluded[i]] > tSupply) return (_rTotal, _totalSupply);
            rSupply = rSupply.sub(_reflectionOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tokensOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_totalSupply)) return (_rTotal, _totalSupply);
        return (rSupply, tSupply);
    }

    /**
        @notice get tValues
        @param tAmount uint256 amount to get off of
        @return tTransferAmount uint256
        @return tFee uint256
        @return tLiquidity uint256
     */
    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tFee       = calculateFee(tAmount, _taxFee);
        uint256 tLiquidity = calculateFee(tAmount, _liquidityFee);
        uint256 tTransferAmount = tAmount.sub(tFee);
        tTransferAmount = tTransferAmount.sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    /**
        @notice get current rate based off of current supply
        @return r/t uint256
    */
    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

}
