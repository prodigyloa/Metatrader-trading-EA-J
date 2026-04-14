//+------------------------------------------------------------------+
//|                                                   Parameters.mqh |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

//--- Risk base selection
enum ENUM_RISK_BASE
  {
   RISK_BASE_EQUITY=1,        //EQUITY
   RISK_BASE_BALANCE=2,       //BALANCE
   RISK_BASE_FREEMARGIN=3,    //FREE MARGIN
  };

//--- Position size mode
enum ENUM_RISK_DEFAULT_SIZE
  {
   RISK_DEFAULT_FIXED=1,      //FIXED SIZE
   RISK_DEFAULT_AUTO=2,       //AUTOMATIC SIZE BASED ON RISK
  };

//--- Stop loss mode
enum ENUM_MODE_SL
  {
   SL_FIXED=0,                //FIXED STOP LOSS (points)
   SL_AUTO=1,                 //AUTOMATIC STOP LOSS (ATR-based)
  };

//--- Take profit mode
enum ENUM_MODE_TP
  {
   TP_FIXED=0,                //FIXED TAKE PROFIT (points)
   TP_AUTO=1,                 //AUTOMATIC TAKE PROFIT (R:R ratio)
  };

//--- Signal strategy selection
enum ENUM_PP_STRATEGY
  {
   STRATEGY_EMA_PINBAR=0,     //EMA Trend + Pin Bar
   STRATEGY_EMA_CROSSOVER=1,  //EMA Crossover + RSI Filter
  };

//--- Trade signal type
enum ENUM_MODE_TRADE_SIGNAL
  {
   BUY_SIGNAL=0,              //Buy signal
   SELL_SIGNAL=1,             //Sell signal
   NO_SIGNAL=2,               //No signal
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

//--- Funded Account Rules
input string Comment_Funded = "==========";                          //=== FUNDED ACCOUNT RULES ===
input double InpInitialBalance      = 0.0;                           //Initial Balance Override (0=auto-detect)
input double InpMaxDailyDrawdown    = 5.0;                           //Max Daily Drawdown % (prop firm rule)
input double InpMaxOverallDrawdown  = 10.0;                          //Max Overall Drawdown % (permanent stop)
input double InpProfitTarget        = 8.0;                           //Profit Target % (challenge complete)
input bool   InpEnableConsistency   = false;                         //Enable Consistency Rule
input double InpConsistencyLimit    = 50.0;                          //Max Single Day Profit as % of Total Profit

//--- Strategy Settings
input string Comment_Strategy = "==========";                        //=== STRATEGY SETTINGS ===
input ENUM_PP_STRATEGY InpStrategy  = STRATEGY_EMA_PINBAR;           //Signal Strategy
input int    InpTrendEmaPeriod      = 50;                            //Trend Filter EMA Period
input int    InpFastEmaPeriod       = 8;                             //Fast EMA Period (Crossover Strategy)
input int    InpSlowEmaPeriod       = 21;                            //Slow EMA Period (Crossover Strategy)
input int    InpRsiPeriod           = 14;                            //RSI Period
input double InpRsiOverbought       = 55.0;                          //RSI Sell Filter Threshold
input double InpRsiOversold         = 45.0;                          //RSI Buy Filter Threshold
input int    InpPinBarWickPct       = 65;                            //Min Pin Bar Wick % of Candle Range
input int    InpMinCandlePoints     = 100;                           //Min Candle Size in Points (filter doji)

//--- Risk Management
input string Comment_Risk = "==========";                            //=== RISK MANAGEMENT ===
input ENUM_RISK_DEFAULT_SIZE InpRiskDefaultSize = RISK_DEFAULT_AUTO; //Position Size Mode
input double InpDefaultLotSize      = 0.01;                          //Fixed Lot Size (or fallback)
input ENUM_RISK_BASE InpRiskBase    = RISK_BASE_BALANCE;             //Risk Base
input double InpMaxRiskPerTrade     = 0.5;                           //Risk Per Trade (% of base)
input double InpMinLotSize          = 0.01;                          //Minimum Lot Size Allowed
input double InpMaxLotSize          = 100.0;                         //Maximum Lot Size Allowed
input int    InpMaxSpread           = 50;                            //Maximum Spread Allowed (points)
input int    InpSlippage            = 5;                             //Maximum Slippage (points)
input int    InpMaxPositions        = 2;                             //Max Concurrent Open Positions

//--- Stop Loss Settings
input string Comment_SL = "----------";                              //--- Stop Loss Settings ---
input ENUM_MODE_SL InpStopLossMode  = SL_AUTO;                       //Stop Loss Mode
input int    InpDefaultStopLoss     = 500;                           //Default Stop Loss in Points (fallback)
input int    InpAtrPeriod           = 14;                            //ATR Period
input double InpAtrMultiplier       = 1.5;                           //ATR Multiplier for SL Distance

//--- Take Profit Settings
input string Comment_TP = "----------";                              //--- Take Profit Settings ---
input ENUM_MODE_TP InpTakeProfitMode = TP_AUTO;                      //Take Profit Mode
input int    InpDefaultTakeProfit   = 1000;                          //Default Take Profit in Points (fallback)
input double InpRRRatio             = 2.0;                           //Risk:Reward Ratio (TP = SL x RR)

//--- Trading Hours
input string Comment_Hours = "==========";                           //=== TRADING HOURS ===
input bool   InpUseTradingHours     = false;                         //Limit Trading to Session Hours
input int    InpSessionStart        = 7;                             //Session Start Hour (broker server time)
input int    InpSessionEnd          = 21;                            //Session End Hour (broker server time)

//--- General Settings
input string Comment_General = "==========";                         //=== GENERAL SETTINGS ===
input int    InpMagicNumber         = 202401;                        //Magic Number
input string InpComment             = __FILE__;                      //Trade Comment
input ENUM_TIMEFRAMES InpTimeFrame  = PERIOD_CURRENT;                //Timeframe

//--- Dashboard Settings
input string Comment_Dashboard = "==========";                       //=== DASHBOARD SETTINGS ===
input bool   InpShowDashboard       = true;                          //Show Chart Dashboard Panel
input ENUM_BASE_CORNER InpDashboardCorner = CORNER_LEFT_UPPER;       //Dashboard Corner
input int    InpDashboardX          = 10;                            //Dashboard X Distance (pixels)
input int    InpDashboardY          = 20;                            //Dashboard Y Distance (pixels)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+

//--- Symbol & tick data
string   gSymbol = Symbol();
MqlTick  last_tick;
MqlDateTime dt;

//--- Indicator values
double   gAtr = 0.0;

//--- Position tracking
int      gTotalBuyPositions  = 0;
int      gTotalSellPositions = 0;
int      gTotalPositions     = 0;

//--- EA state flags
bool     gIsOperatingHours  = false;
bool     gIsPreChecksOk     = false;
bool     gIsSpreadOK        = false;

//--- Trade execution
double   gLotSize            = 0.01;
int      gOrderOpRetry       = 10;
datetime gLastBarTraded      = 0;

//--- Funded account state (persisted via GlobalVariables)
double   gInitialBalance     = 0.0;
double   gDailyStartEquity   = 0.0;
double   gPeakEquity         = 0.0;
int      gDaysTraded         = 0;
bool     gDailyLimitHit      = false;
bool     gMaxDDHit           = false;
bool     gTargetReached      = false;
datetime gLastDayReset       = 0;

//--- GlobalVariable name prefixes (unique per magic number)
string   GV_PREFIX = "PPA_" + IntegerToString(InpMagicNumber) + "_";
//+------------------------------------------------------------------+
