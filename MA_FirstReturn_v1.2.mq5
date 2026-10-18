#property copyright "Custom indicator"
#property version "1.20"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots 4
#property indicator_label1 "SMA Fast"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrGoldenrod
#property indicator_label2 "SMA Slow"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrMediumSeaGreen
#property indicator_label3 "First Return BUY"
#property indicator_type3 DRAW_ARROW
#property indicator_color3 clrDodgerBlue
#property indicator_width3 2
#property indicator_label4 "First Return SELL"
#property indicator_type4 DRAW_ARROW
#property indicator_color4 clrTomato
#property indicator_width4 2
#include "FirstReturnCore.mqh"

input group "Moving averages / ATR"
input int InpFastPeriod=25;
input int InpSlowPeriod=55;
input int InpATRPeriod=14;
input int InpSlopeBars=3;
input double InpSlopeATR=0.05;
input group "Range / setup"
input int InpRangeBars=20;
input double InpRangeWidthATR=4.0;
input int InpPairBars=10;
input int InpExpiryBars=30;
input double InpDepartureATR=0.5;
input double InpTouchATR=0.1;
input int InpHistoryBars=5000;
input group "Display / notification"
input double InpArrowOffsetATR=0.3;
input bool InpPopup=true;
input bool InpPush=true;
input bool InpSound=false;
input string InpSoundFile="alert.wav";

double FastPlot[],SlowPlot[],BuyPlot[],SellPlot[];
double fast[],slow[],atr[];
int fastHandle=INVALID_HANDLE,slowHandle=INVALID_HANDLE,atrHandle=INVALID_HANDLE;
FRState committed;
FRParams cfg;
datetime lastBar=0;
datetime liveStartBar=0;
int lastTotal=0, newestIndex=0;
bool booted=false;
struct LiveEvent { datetime bar,cross; int direction; double price; };
LiveEvent liveEvents[];
#include "FirstReturnCSV.mqh"

int OnInit()
{
   if(InpFastPeriod<1 || InpSlowPeriod<=InpFastPeriod || InpATRPeriod<1 ||
      InpSlopeBars<1 || InpRangeBars<2 || InpSlopeATR<0 || InpTouchATR<0 ||
      InpDepartureATR<=InpTouchATR || InpRangeWidthATR<=0 || InpPairBars<0 ||
      InpExpiryBars<1 || InpHistoryBars<100 || InpArrowOffsetATR<0)
      return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,FastPlot,INDICATOR_DATA);
   SetIndexBuffer(1,SlowPlot,INDICATOR_DATA);
   SetIndexBuffer(2,BuyPlot,INDICATOR_DATA);
   SetIndexBuffer(3,SellPlot,INDICATOR_DATA);
   ArraySetAsSeries(FastPlot,true); ArraySetAsSeries(SlowPlot,true);
   ArraySetAsSeries(BuyPlot,true); ArraySetAsSeries(SellPlot,true);
   ArraySetAsSeries(fast,true); ArraySetAsSeries(slow,true); ArraySetAsSeries(atr,true);
   for(int k=0;k<4;k++) PlotIndexSetDouble(k,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(2,PLOT_ARROW,233); PlotIndexSetInteger(3,PLOT_ARROW,234);
   fastHandle=iMA(_Symbol,_Period,InpFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   slowHandle=iMA(_Symbol,_Period,InpSlowPeriod,0,MODE_SMA,PRICE_CLOSE);
   atrHandle=iATR(_Symbol,_Period,InpATRPeriod);
   if(fastHandle==INVALID_HANDLE || slowHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE)
      return INIT_FAILED;
   cfg.pairBars=InpPairBars; cfg.expiryBars=InpExpiryBars;
   cfg.slopeATR=InpSlopeATR; cfg.touchATR=InpTouchATR; cfg.departureATR=InpDepartureATR;
   FRReset(committed);
   IndicatorSetString(INDICATOR_SHORTNAME,"MA First Return 1.2 CSV ("+
                      IntegerToString(InpFastPeriod)+","+IntegerToString(InpSlowPeriod)+")");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   if(!OpenCSV()) return INIT_FAILED;
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(csvHandle!=INVALID_HANDLE) { FileFlush(csvHandle); FileClose(csvHandle); csvHandle=INVALID_HANDLE; }
   if(fastHandle!=INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle!=INVALID_HANDLE) IndicatorRelease(slowHandle);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
}
void PlotSignal(const int shift,const int direction,const double price)
{
   if(direction>0) BuyPlot[shift]=price; else SellPlot[shift]=price;
}
void Notify(const int direction,const datetime bar,const double price)
{
   string message=StringFormat("MA First Return | %s %s | %s | %s | price %s",
      _Symbol,EnumToString(_Period),(direction>0?"BUY":"SELL"),
      TimeToString(bar,TIME_DATE|TIME_MINUTES),DoubleToString(price,_Digits));
   Print(message);
   // Tester validates signals via chart and CSV; external notifications are disabled.
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(InpPopup) Alert(message);
   if(InpSound) PlaySound(InpSoundFile);
   if(InpPush && !SendNotification(message))
      Print("Push failed. Error=",GetLastError(),". Check MT5 notification settings.");
}
int OnCalculate(const int rates_total,const int prev_calculated,
   const datetime &time[],const double &open[],const double &high[],
   const double &low[],const double &close[],const long &tick_volume[],
   const long &volume[],const int &spread[])
{
   ArraySetAsSeries(time,true); ArraySetAsSeries(open,true); ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true); ArraySetAsSeries(close,true);
   int warm=(int)MathMax(InpSlowPeriod,InpATRPeriod)+InpSlopeBars+InpRangeBars+2;
   if(rates_total<warm+3) return 0;
   int count=(int)MathMin(rates_total,InpHistoryBars+warm);
   bool rebuild=(!booted || prev_calculated==0 || time[0]!=lastBar || rates_total!=lastTotal);
   if(rebuild)
   {
      if(CopyBuffer(fastHandle,0,0,count,fast)!=count ||
         CopyBuffer(slowHandle,0,0,count,slow)!=count ||
         CopyBuffer(atrHandle,0,0,count,atr)!=count) return prev_calculated;
      // Fixed for this instance, including history reloads and prev_calculated=0.
      if(liveStartBar==0) liveStartBar=time[0];
      ArrayInitialize(FastPlot,EMPTY_VALUE); ArrayInitialize(SlowPlot,EMPTY_VALUE);
      ArrayInitialize(BuyPlot,EMPTY_VALUE); ArrayInitialize(SellPlot,EMPTY_VALUE);
      for(int j=0;j<count;j++) { FastPlot[j]=fast[j]; SlowPlot[j]=slow[j]; }
      FRReset(committed);
      activeTop=0; activeBottom=0; activeBreakTime=0; activeCrossTime=0;
      int start=count-warm-1;
      for(int i=start;i>=1;i--)
      {
         FRBar b;
         b.index=start-i;
         b.fast=fast[i]; b.slow=slow[i]; b.fastPast=fast[i+InpSlopeBars];
         b.slowPast=slow[i+InpSlopeBars]; b.atr=atr[i];
         b.low=low[i]; b.high=high[i]; b.close=close[i];
         b.cross=0;
         if(fast[i]>slow[i] && fast[i+1]<=slow[i+1]) b.cross=1;
         if(fast[i]<slow[i] && fast[i+1]>=slow[i+1]) b.cross=-1;
         double top=high[i+1],bottom=low[i+1];
         for(int j=i+2;j<=i+InpRangeBars;j++)
         { top=MathMax(top,high[j]); bottom=MathMin(bottom,low[j]); }
         // The breakout candle is excluded from both range and ATR reference.
         b.rangeValid=(atr[i+1]>0 && top-bottom<=atr[i+1]*InpRangeWidthATR);
         b.breakout=0;
         if(close[i]>top) b.breakout=1;
         if(close[i]<bottom) b.breakout=-1;
         // Preserve observed live signals even if the candle subsequently changes.
         int forced=-1;
         for(int e=ArraySize(liveEvents)-1;e>=0;e--)
            if(liveEvents[e].bar==time[i]) { forced=e; break; }
         FRState before=committed;
         // A tick signal belongs to the cross that existed DURING this candle.
         // Consume it before closing-bar events; a reverse cross at the close
         // must remain a fresh, unconsumed generation.
         if(forced>=0)
         {
            int priorCrossShift=start-committed.crossBar;
            if(priorCrossShift>=0 && priorCrossShift<count &&
               time[priorCrossShift]==liveEvents[forced].cross)
               committed.consumed=true;
         }
         bool historical=(time[i]<liveStartBar);
         // Runtime closed bars update preparation ONLY. Never manufacture a
         // touch from final SMA/ATR combined with an earlier intrabar extreme.
         int signal=FRCommit(committed,b,cfg,historical);
         if(b.cross!=0) activeCrossTime=time[i];
         if(committed.breakDir==0)
         { activeBreakTime=0; activeTop=0; activeBottom=0; }
         else if(committed.breakBar!=before.breakBar || committed.breakDir!=before.breakDir)
         { activeBreakTime=time[i]; activeTop=top; activeBottom=bottom; }
         if(forced>=0)
         {
            PlotSignal(i,liveEvents[forced].direction,liveEvents[forced].price);
         }
         else if(signal!=0)
            PlotSignal(i,signal,(signal>0?low[i]-atr[i]*InpArrowOffsetATR:
                                        high[i]+atr[i]*InpArrowOffsetATR));
         if(time[i]>csvLastBar)
         {
            bool initial=!csvInitialized;
            if(!initial || InpCSVHistory)
            {
               int plotted=forced>=0?liveEvents[forced].direction:signal;
               double arrow=plotted>0?BuyPlot[i]:(plotted<0?SellPlot[i]:0);
               string why="BAR_SNAPSHOT";
               if(before.breakDir!=0 && b.index-before.breakBar>cfg.expiryBars) why="EXPIRED";
               if(b.cross!=0) why=(before.crossDir!=0?"NEW_CROSS_RESET":"CROSS_CONFIRMED");
               if(activeBreakTime==time[i]) why+="|BREAKOUT_CONFIRMED";
               if(!before.departed && committed.departed) why+="|DEPARTURE_CONFIRMED";
               if(plotted!=0) why+=(forced>=0?"|LIVE_SIGNAL_RETAINED":"|OHLC_TOUCH_APPROX");
               string source=historical?"OHLC_APPROX":"CLOSED_PREPARATION";
               CSVRow(historical?"HISTORY_BAR":"CLOSED_BAR",source,time[i],open[i],high[i],low[i],
                  b,before,committed,top,bottom,atr[i+1],plotted,arrow,why);
               if(InpCSVStateChanges && CSVState(before,b)!=CSVState(committed,b))
                  CSVRow("STATE_CHANGE",source,time[i],open[i],high[i],low[i],
                     b,before,committed,top,bottom,atr[i+1],plotted,arrow,why);
            }
            csvLastBar=time[i];
         }
      }
      csvInitialized=true;
      csvLastState="";
      if(csvHandle!=INVALID_HANDLE) FileFlush(csvHandle);
      newestIndex=start;
      lastBar=time[0]; lastTotal=rates_total; booted=true;
   }
   // Partial CopyBuffer writes are isolated from the historical arrays.
   double f0[1],s0[1];
   if(CopyBuffer(fastHandle,0,0,1,f0)!=1 || CopyBuffer(slowHandle,0,0,1,s0)!=1)
      return rates_total;
   FastPlot[0]=f0[0]; SlowPlot[0]=s0[0];
   for(int e=ArraySize(liveEvents)-1;e>=0;e--)
      if(liveEvents[e].bar==time[0])
      { PlotSignal(0,liveEvents[e].direction,liveEvents[e].price); return rates_total; }
   // Work on a copy: no provisional cross, breakout or departure is committed.
   FRState trial=committed;
   FRState liveBefore=committed;
   FRBar tick;
   tick.index=newestIndex; tick.cross=0; tick.breakout=0; tick.rangeValid=false;
   tick.fast=f0[0]; tick.slow=s0[0];
   tick.fastPast=fast[InpSlopeBars]; tick.slowPast=slow[InpSlopeBars];
   tick.atr=atr[1]; // fixed latest confirmed ATR for intrabar thresholds
   tick.low=close[0]; tick.high=close[0]; tick.close=close[0];
   int signal=FRStep(trial,tick,cfg);
   if(signal!=0)
   {
      double price=(signal>0?low[0]-tick.atr*InpArrowOffsetATR:
                              high[0]+tick.atr*InpArrowOffsetATR);
      int n=ArraySize(liveEvents); ArrayResize(liveEvents,n+1);
      liveEvents[n].bar=time[0]; liveEvents[n].direction=signal; liveEvents[n].price=price;
      int crossShift=newestIndex-committed.crossBar;
      liveEvents[n].cross=(crossShift>=0 && crossShift<count?time[crossShift]:0);
      committed.consumed=true;
      PlotSignal(0,signal,price);
      CSVRow("LIVE_SIGNAL","TICK",time[0],open[0],high[0],low[0],tick,
         liveBefore,committed,0,0,0,signal,price,"FIRST_RETURN_TOUCH");
      if(csvHandle!=INVALID_HANDLE) FileFlush(csvHandle);
      Notify(signal,time[0],close[0]);
   }
   else if(InpCSVStateChanges && csvHandle!=INVALID_HANDLE)
   {
      string stateNow=CSVState(committed,tick);
      if(stateNow!=csvLastState)
      {
         CSVRow("STATE_CHANGE","TICK",time[0],open[0],high[0],low[0],tick,
            committed,committed,0,0,0,0,0,"INTRABAR_STATUS");
         csvLastState=stateNow;
         FileFlush(csvHandle);
      }
   }
   return rates_total;
}
