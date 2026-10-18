// CSV diagnostics do not alter FRStep or its input data.
input group "CSV diagnostics"
input bool InpCSVEnabled=true;
input bool InpCSVCommon=true;
input bool InpCSVHistory=true;
input bool InpCSVStateChanges=true;

int csvHandle=INVALID_HANDLE;
datetime csvLastBar=0;
bool csvInitialized=false;
string csvLastState="",csvPath="";
double activeTop=0,activeBottom=0;
datetime activeBreakTime=0,activeCrossTime=0;
string DirName(const int d) { return d>0?"BUY":(d<0?"SELL":"NONE"); }
string Num(const double d) { return DoubleToString(d,8); }
string Stamp(const datetime t) { return t>0?TimeToString(t,TIME_DATE|TIME_SECONDS):""; }
string CSVState(FRState &s,FRBar &b)
{
   if(s.crossDir==0) return "WAIT_CROSS";
   if(s.consumed) return "DETECTED";
   if(s.breakDir==0 || b.index-s.breakBar>cfg.expiryBars) return "WAIT_BREAKOUT";
   if(s.breakDir!=s.crossDir) return "DIRECTION_MISMATCH";
   if(MathAbs(s.crossBar-s.breakBar)>cfg.pairBars) return "PAIR_TOO_FAR";
   if(b.index<=MathMax(s.crossBar,s.breakBar)) return "WAIT_NEXT_BAR";
   if(!FRTrend(s,b,cfg)) return "WAIT_SLOPE";
   if(!s.departed) return "WAIT_DEPARTURE";
   return "WAIT_RETURN";
}
bool OpenCSV()
{
   if(!InpCSVEnabled) return true;
   string symbol=_Symbol;
   StringReplace(symbol,"\\","_"); StringReplace(symbol,"/","_");
   StringReplace(symbol,":","_"); StringReplace(symbol,"*","_");
   StringReplace(symbol,"?","_"); StringReplace(symbol,"\"","_");
   StringReplace(symbol,"<","_"); StringReplace(symbol,">","_"); StringReplace(symbol,"|","_");
   string name=StringFormat("MA_FirstReturn_v1.2_%s_%s_%I64d_%I64u.csv",
       symbol,EnumToString(_Period),ChartID(),GetMicrosecondCount());
   csvPath="MA_FirstReturn\\"+name;
   int common=(InpCSVCommon?FILE_COMMON:0);
   FolderCreate("MA_FirstReturn",common);
   csvHandle=FileOpen(csvPath,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|common,',',CP_UTF8);
   if(csvHandle==INVALID_HANDLE)
   { Print("CSV OPEN FAILED: ",csvPath," error=",GetLastError()); return false; }
   FileWrite(csvHandle,"event","source","observed_time","observed_msc","bar_time","symbol","timeframe",
      "state_before","state_after","reason","signal_direction","setup_direction",
      "open","high","low","close","fast_ma","slow_ma","atr_used","range_atr",
      "fast_delta","slow_delta","fast_delta_atr","slow_delta_atr","trend_ok",
      "range_top","range_bottom","range_width_atr","range_valid","cross_event","breakout_event",
      "active_cross_time","active_break_time","active_range_top","active_range_bottom",
      "pair_gap_bars","break_age_bars","departed_before","departed_after","consumed",
      "touch_lower","touch_upper","arrow_price","parameters");
   FileFlush(csvHandle);
   string root=InpCSVCommon?TerminalInfoString(TERMINAL_COMMONDATA_PATH):TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL5";
   Print("CSV output: ",root,"\\Files\\",csvPath);
   Print("CSV times use broker/server time; HISTORY_BAR is OHLC approximation; runtime signals are TICK only (v1.2).");
   return true;
}
void CSVRow(const string event,const string source,const datetime barTime,
   const double openPrice,const double highPrice,const double lowPrice,
   FRBar &b,FRState &before,FRState &after,const double top,const double bottom,
   const double rangeATR,const int signal,const double arrowPrice,const string reason)
{
   if(csvHandle==INVALID_HANDLE) return;
   MqlTick quote; ZeroMemory(quote);
   SymbolInfoTick(_Symbol,quote);
   string parameters=StringFormat("fast=%d|slow=%d|atr=%d|slope_bars=%d|slope_atr=%g|range_bars=%d|range_atr=%g|pair=%d|expiry=%d|departure=%g|touch=%g|history=%d|offset=%g",
      InpFastPeriod,InpSlowPeriod,InpATRPeriod,InpSlopeBars,InpSlopeATR,InpRangeBars,
      InpRangeWidthATR,InpPairBars,InpExpiryBars,InpDepartureATR,InpTouchATR,InpHistoryBars,InpArrowOffsetATR);
   string gap=after.crossDir!=0 && after.breakDir!=0?IntegerToString((int)MathAbs(after.crossBar-after.breakBar)):"";
   string age=after.breakDir!=0?IntegerToString(b.index-after.breakBar):"";
   uint written=FileWrite(csvHandle,event,source,Stamp(TimeCurrent()),(string)quote.time_msc,Stamp(barTime),_Symbol,EnumToString(_Period),
      CSVState(before,b),CSVState(after,b),reason,DirName(signal),DirName(after.crossDir),
      Num(openPrice),Num(highPrice),Num(lowPrice),Num(b.close),Num(b.fast),Num(b.slow),Num(b.atr),Num(rangeATR),
      Num(b.fast-b.fastPast),Num(b.slow-b.slowPast),
      (b.atr>0?Num((b.fast-b.fastPast)/b.atr):""),(b.atr>0?Num((b.slow-b.slowPast)/b.atr):""),
      (int)FRTrend(after,b,cfg),(rangeATR>0?Num(top):""),(rangeATR>0?Num(bottom):""),(rangeATR>0?Num((top-bottom)/rangeATR):""),
      (source=="TICK"?"":IntegerToString((int)b.rangeValid)),DirName(b.cross),DirName(b.breakout),Stamp(activeCrossTime),Stamp(activeBreakTime),
      Num(activeTop),Num(activeBottom),gap,age,(int)before.departed,(int)after.departed,(int)after.consumed,
      Num(b.fast-b.atr*cfg.touchATR),Num(b.fast+b.atr*cfg.touchATR),(signal!=0?Num(arrowPrice):""),parameters);
   if(written==0)
      Print("CSV WRITE FAILED: ",csvPath," error=",GetLastError());
}
