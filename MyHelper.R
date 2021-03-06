library("termstrc")
#######################################################################
############ 中国版计算方式,不算连续复利，而是按年付息 ################
############ 计算收益率、价格、久期的三个函数          ################
bond_yields_China = function (cashflows, m, searchint = c(-1, 1), tol = 1e-10) 
{
  
  if (!is.matrix(cashflows)) 
    cashflows <- as.matrix(cashflows)
  if (!is.matrix(m)) 
    m <- as.matrix(m)
  bondyields <- matrix(0, nrow = ncol(cashflows), ncol = 2)
  bondyields[, 1] <- apply(m, 2, max)
  for (i in seq_len(ncol(cashflows))) {
    pvcashflows <- function(y) {
      t(cashflows[, i]) %*% (1/(1+y)^m[, i])##这里修改了，将连续复利改为按年计息
    }
    bondyields[i, 2] <- uniroot(pvcashflows, searchint, tol = tol, 
                                maxiter = 3000)$root
  }
  rownames(bondyields) <- colnames(cashflows)
  colnames(bondyields) <- c("Maturity", "Yield")
  bondyields
}
##根据YTM计算bond的现价(全价)
bond_pricesDirty_China = function (cf_p, m_p, y, frequency)
{
  y = y/frequency
  y <- matrix(rep(y, nrow(m_p)), ncol = ncol(m_p), byrow = TRUE)
  d <- cf_p / (1+y)^m_p
  price = apply(d,2,"sum")
  price
}
##根据YTM计算bond的现价(净价)
bond_pricesClean_China = function (cf_p, m_p, y, frequency)
{
  y = y/frequency
  y <- matrix(rep(y, nrow(m_p)), ncol = ncol(m_p), byrow = TRUE)
  d <- cf_p / (1+y)^m_p
  price = apply(d,2,"sum")
  price = price - cf_p[1,] * (1 - m_p[1,])
  price
}
##计算基点价值
InitBPV = function(bonddata, group, QuoteBond) 
{
  bonddata_before     = InitBondPrice(bonddata,group,QuoteBond,BondYTMBasis = 0)
  bonddata_YTMup1BP   = InitBondPrice(bonddata,group,QuoteBond,BondYTMBasis = 0.0001)
  bonddata_YTMdown1BP = InitBondPrice(bonddata,group,QuoteBond,BondYTMBasis = -0.0001)
  BPV = (bonddata_YTMdown1BP[[group]]$PRICE+bonddata_YTMdown1BP[[group]]$ACCRUED-
           bonddata_YTMup1BP[[group]]$PRICE-bonddata_YTMup1BP[[group]]$ACCRUED)/2*10000
  
  bonddata[[group]]$BPV = BPV
  bonddata
}

##从数据集中删除一条债券的信息
rm_bond_China = function (bonddata, group, ISIN)
{
  i = which(bonddata[[group]]$ISIN == ISIN)
  bonddata[[group]]$ISIN = bonddata[[group]]$ISIN[-i] 
  bonddata[[group]]$MATURITYDATE = bonddata[[group]]$MATURITYDATE[-i] 
  bonddata[[group]]$ISSUEDATE = bonddata[[group]]$ISSUEDATE[-i] 
  bonddata[[group]]$COUPONRATE = bonddata[[group]]$COUPONRATE[-i] 
  bonddata[[group]]$PRICE = bonddata[[group]]$PRICE[-i] 
  bonddata[[group]]$ACCRUED = bonddata[[group]]$ACCRUED[-i]
  bonddata[[group]]$FREQUENCY = bonddata[[group]]$FREQUENCY[-i]
  
  i = which(bonddata[[group]]$CASHFLOWS$ISIN == ISIN)
  bonddata[[group]]$CASHFLOWS$ISIN = bonddata[[group]]$CASHFLOWS$ISIN[-i]
  bonddata[[group]]$CASHFLOWS$CF = bonddata[[group]]$CASHFLOWS$CF[-i]
  bonddata[[group]]$CASHFLOWS$DATE = bonddata[[group]]$CASHFLOWS$DATE[-i]
  bonddata
}

##计算各个CashFlow的期限，注意单位是"年/付息周期",不是年
create_maturities_matrix_China = function (group, include_price = FALSE) 
{
  n_of_cf <- summary(factor(group$CASHFLOWS$ISIN, levels = group$ISIN), 
                     maxsum = 1000)
  n_of_bonds <- length(n_of_cf)
  max_cf <- max(n_of_cf)
  pos_cf <- c(0, cumsum(n_of_cf))
  
  year_diff <- as.numeric(difftime(as.Date(group$CASHFLOW$DATE), 
                                   as.Date(group$TODAY), units = "days"))/365
  
  nextPaymentDate = group$CASHFLOW$DATE[pos_cf+1]
  nextPaymentDate = nextPaymentDate[-length(nextPaymentDate)]
  
  lastPaymentDate = as.Date("2000/01/01","%Y/%m/%d")
  for( i in 1:length(nextPaymentDate))
  {
    if(group$FREQUENCY[i] == 1)
      lastPaymentDate[i] = seq(nextPaymentDate[i],by = "-1 year",length = 2)[2]
    else if (group$FREQUENCY[i] == 2)
      lastPaymentDate[i] = seq(nextPaymentDate[i],by = "-6 month",length = 2)[2]
  }
  daysDiff = as.integer(as.Date(nextPaymentDate) - as.Date(group$TODAY))
  paymentInterval = as.integer(nextPaymentDate-lastPaymentDate)
  
  ##YTM计算公式中的乘子
  w = daysDiff/paymentInterval
  
  MATURITYMATRIX = matrix(data = w,nr = max_cf,nc = n_of_bonds,byrow = TRUE)
  MATURITYMATRIX = MATURITYMATRIX+matrix(data = seq(0,max_cf-1,1),nr = max_cf,nc = n_of_bonds,byrow = FALSE)
  c(rep(1,n_of_cf[i]),rep(0, max_cf - n_of_cf[i]))
  
  cf <- mapply(function(i) c(rep(1,n_of_cf[i]),rep(0, max_cf - n_of_cf[i])), 1:n_of_bonds)
  MATURITYMATRIX = MATURITYMATRIX * cf
  colnames(MATURITYMATRIX) <- group$ISIN
  MATURITYMATRIX
}
##########################################################################
###############   Function: Reset current Date          ##################
###############   Remove obsolete bond,Recalculate CF   ##################
##注意这里对TF相关信息没有后续修改,最好在调用AddTFInfo前调用本函数
ResetToday = function(bonddata,group,today=Sys.Date(),removeNotIssued = TRUE,removeObsoleteBond = TRUE,removeObsoleteCF = TRUE)
{
  bonddata[[group]]$TODAY = today
  ##Remove not issue yet bond data
  if( removeNotIssued )
  {
    i = 1
    while( i <= length(bonddata[[group]]$ISSUEDATE))
    {
      if(bonddata[[group]]$ISSUEDATE[i] > bonddata[[group]]$TODAY)##在“today”尚未发行的bond
      {
        bonddata = rm_bond_China(bonddata, group, bonddata[[group]]$ISIN[i])
      }
      else
        i = i+1
    }
    print("RemoveNotIssued Completed")
  }
  ##Remove obsolete bond data
  if( removeObsoleteBond )
  {
    i = 1  
    while( i <= length(bonddata[[group]]$MATURITYDATE))
    {
      if(bonddata[[group]]$MATURITYDATE[i] < bonddata[[group]]$TODAY)##已经退市的bond
      {
        bonddata = rm_bond_China(bonddata, group, bonddata[[group]]$ISIN[i])
      }
      else
        i = i+1
    }
    print("Remove obsolete bond data Completed")
  }
  if( removeObsoleteCF )
  {
    ##Remove obsolete CF data
    i = 1
    print(length(bonddata[[group]]$CASHFLOWS$DATE))
    while( i <= length(bonddata[[group]]$CASHFLOWS$DATE))
    {      
      if(bonddata[[group]]$CASHFLOWS$DATE[i] < bonddata[[group]]$TODAY)##过期的Cashflow
      {      
        bonddata[[group]]$CASHFLOWS$DATE = bonddata[[group]]$CASHFLOWS$DATE[-i]
        bonddata[[group]]$CASHFLOWS$CF   = bonddata[[group]]$CASHFLOWS$CF[-i]
        bonddata[[group]]$CASHFLOWS$ISIN = bonddata[[group]]$CASHFLOWS$ISIN[-i]  
        print(bonddata[[group]]$ISIN)
      }
      else
        i = i+1
    }
    print("Remove obsolete CF data Completed")
  }
  bonddata
}

##########################################################################
###############   Function: 将从CSV文件中读取获得的原始数据   ############
###############             转换为termstr需要的数据格式。     ############
###############             多一列数据付息频率FREQUENCY       ############
InitGovBondInfo = function(GovBondInfo)
{
  ISIN          = as.character(GovBondInfo$code.IB)
  MATURITYDATE  = as.Date(GovBondInfo$maturitydate,"%Y/%m/%d")
  ISSUEDATE     = as.Date(GovBondInfo$issuedate,"%Y/%m/%d")
  COUPONRATE    = GovBondInfo$couponrate/100
  FREQUENCY     = GovBondInfo$frequency
  PRICE         = rep(100,length(ISIN))
  ACCRUED       = rep(0,length(ISIN))
  YTM           = rep(0,length(ISIN))
  BPV           = rep(0,length(ISIN))
  CASHFLOW_CF   = NULL
  CASHFLOW_DATE = as.Date("2000/01/01","%Y/%m/%d")
  CASHFLOW_ISIN = NULL
  
  k=0
  
  for( i in  1:length(ISIN))
  {
    j = 1
    if( FREQUENCY[i] == 1 )
    {
      date_tmp = seq(ISSUEDATE[i],by = "1 year", length = j+1)[j+1]
      while(seq(date_tmp,by = "-1 year", length = j+1)[j+1]>ISSUEDATE[i])
        date_tmp=date_tmp-1
    }
    else if( FREQUENCY[i] == 2 )
    {
      date_tmp = seq(ISSUEDATE[i],by = "6 month", length = j+1)[j+1]
      while(seq(date_tmp,by = "-6 months", length = j+1)[j+1]>ISSUEDATE[i])
        date_tmp=date_tmp-1
    }
    else
      cat("Error in data,FREQUENCY is not 1 or 2")
    
    
    while(date_tmp < MATURITYDATE[i])
    {
      if( FREQUENCY[i] == 1 )
        CASHFLOW_CF[k+j]    = COUPONRATE[i]*100
      else if( FREQUENCY[i] == 2 )
        CASHFLOW_CF[k+j]    = COUPONRATE[i]*100/2
      else
        cat("Error in data,FREQUENCY is not 1 or 2")
      CASHFLOW_DATE[k+j]  = date_tmp
      CASHFLOW_ISIN[k+j]  = ISIN[i]
      
      j=j+1
      
      if( FREQUENCY[i] == 1 )
      {
        date_tmp = seq(ISSUEDATE[i],by = "1 year", length = j+1)[j+1]
        while(seq(date_tmp,by = "-1 year", length = j+1)[j+1]>ISSUEDATE[i])
          date_tmp=date_tmp-1
      }
      else if( FREQUENCY[i] == 2 )
      {
        date_tmp = seq(ISSUEDATE[i],by = "6 month", length = j+1)[j+1]
        while(seq(date_tmp,by = "-6 months", length = j+1)[j+1]>ISSUEDATE[i])
          date_tmp=date_tmp-1
      }
      else
        cat("Error in data,FREQUENCY is not 1 or 2")
    }
    
    if(date_tmp == MATURITYDATE[i])
    {
      if( FREQUENCY[i] == 1 )
        CASHFLOW_CF[k+j]    = COUPONRATE[i]*100+100
      else if( FREQUENCY[i] == 2 )
        CASHFLOW_CF[k+j]    = COUPONRATE[i]*100/2+100
      else
        cat("Error in data,FREQUENCY is not 1 or 2")
      CASHFLOW_DATE[k+j]  = date_tmp
      CASHFLOW_ISIN[k+j]  = ISIN[i]
      k=k+j
    }
    else
    {
      print("Error in Calculation,date doesn't match")
      print(ISIN[i])
      print(date_tmp)
      print(MATURITYDATE[i])
      print(ISSUEDATE[i])
      k=k+j-1
    }
    
  }
  
  CASHFLOWS = list(ISIN=CASHFLOW_ISIN,CF=CASHFLOW_CF,DATE=CASHFLOW_DATE)
  TODAY = as.Date("2000/01/01","%Y/%m/%d")
  GOV = list(ISIN=ISIN,
             MATURITYDATE=MATURITYDATE,
             ISSUEDATE=ISSUEDATE,
             COUPONRATE=COUPONRATE,
             PRICE=PRICE,
             ACCRUED=ACCRUED,
             YTM=YTM,
             BPV=BPV,
             FREQUENCY=FREQUENCY,
             CASHFLOWS=CASHFLOWS,
             TODAY=TODAY)
  GovBondInfo = list(GOV=GOV)
  GovBondInfo$GOV$CASHFLOWS$DATE = as.Date(GovBondInfo$GOV$CASHFLOWS$DATE)
  GovBondInfo$GOV$TODAY = TODAY
  GovBondInfo
}


##################################################################################
###############   Function: 更新bonddata 的TF是否可交割信息           ############
###############             矩阵的行、列数根据目前的ISIN，TFInfo决定  ############
UpdateDeliverable = function(bonddata,group,TFInfo)
{
  #条件1：4-7年
  minDate <- as.POSIXlt(TFInfo$settlementMonth)
  minDate$year <- minDate$year+4
  minDate = as.Date(minDate)
  maxDate <- as.POSIXlt(TFInfo$settlementMonth)
  maxDate$year <- maxDate$year+7
  maxDate = as.Date(maxDate)
  print(typeof(bonddata[[group]]$MATURITYDATE))
  temp1 = matrix(data = bonddata[[group]]$MATURITYDATE,
                 nr = length(TFInfo$TFname),
                 nc = length(bonddata[[group]]$ISIN),
                 byrow = TRUE)
  test1 = temp1 >= minDate & temp1 <= maxDate
  #条件2：已经发行
  temp2 = matrix(data = bonddata[[group]]$ISSUEDATE,
                 nr = length(TFInfo$TFname),
                 nc = length(bonddata[[group]]$ISIN),
                 byrow = TRUE)
  
  test2 = temp2 < TFInfo$settlementDate
  ##################################################
  #条件3：（暂未加入）在交割月可以转托管
  ##################################################
  deliverable = test1 & test2
  dimnames(deliverable) = list(TFInfo$TFname,bonddata[[group]]$ISIN)
  
  bonddata[[group]]$deliverable = deliverable
  
  bonddata
}
##########################################################################
###############   Function: 给债券基础信息加上TF相关参数      ############
###############             包括：是否为可交割券，CF因子      ############
AddTFInfo = function(bonddata,group,TFInfo)
{ 
  bonddata[[group]]$TFname = TFInfo$TFname
  bonddata[[group]]$TFprice = rep(100,length(TFInfo$TFname))
  
  bonddata = UpdateDeliverable(bonddata,group,TFInfo)
  
  conversionFactor = matrix(data=0,nr = length(TFInfo$TFname),nc = length(bonddata[[group]]$ISIN))
  accruedInterest  = matrix(data=0,nr = length(TFInfo$TFname),nc = length(bonddata[[group]]$ISIN))
  for( i in 1:length(TFInfo$TFname))
  {
    if(bonddata[[group]]$TODAY >= TFInfo$settlementDate[i])
    {
      conversionFactor[i,]= rep(0,length(bonddata[[group]]$ISIN))
      accruedInterest[i,]= rep(0,length(bonddata[[group]]$ISIN))
    }
    else
    {
      temp = CalculateTFParam(bonddata,group,TFInfo,i)
      conversionFactor[i,] = temp$CF
      accruedInterest[i,] = temp$ACCRUED
    }    
  }
  
  dimnames(conversionFactor) = list(TFInfo$TFname,bonddata[[group]]$ISIN)
  dimnames(accruedInterest)  = list(TFInfo$TFname,bonddata[[group]]$ISIN)
  bonddata[[group]]$conversionFactor = conversionFactor
  bonddata[[group]]$accruedInterest  = accruedInterest
  
  bonddata
}
##########################################################################
###############   被AddTFInfo调用: 计算CF、accrued            ############
###############   注意这里需要bonddata包括deliverable信息     ############
CalculateTFParam = function(bonddata,group,TFInfo,i)
{
  SettlementDate = TFInfo$settlementDate[i]
  TFNAME         = TFInfo$TFname[i]
  
  temp = ResetToday(bonddata,group, SettlementDate,FALSE,FALSE,FALSE)
  
  cf1 = create_cashflows_matrix(temp[[group]])
  m1 = create_maturities_matrix_China(temp[[group]])
  
  priceClean = bond_pricesClean_China(cf1,m1,rep(0.03,length(bonddata[[group]]$ISIN)),bonddata[[group]]$FREQUENCY)
  ACCRUED = cf1[1,] * (1 - m1[1,])
  ##CF只保留4位小数，后面舍去
  priceClean = floor(priceClean*100)
  CF = as.numeric(priceClean/10000)
  ##ACCRUDE只保留4位小数
  ACCRUED = round(ACCRUED,4)
  
  ##非可交割券的数值没有意义，置为0
  CF[which(bonddata[[group]]$deliverable[TFNAME,] == FALSE)] = 0
  ACCRUED[which(bonddata[[group]]$deliverable[TFNAME,] == FALSE)] = 0
  
  result = data.frame(CF,ACCRUED,priceClean)
  result
}

##########################################################################
##    计算持有期间付息的价值，注意需要经过resetToday调整后计算才正确 #####
CalculateFVcoupon = function(bonddata,group,TFInfo,r)
{
  ##计算下两次付息时间矩阵
  n_of_cf <- summary(factor(bonddata[[group]]$CASHFLOWS$ISIN, levels = bonddata[[group]]$ISIN), maxsum = 1000)
  pos_cf <- c(0, cumsum(n_of_cf))
  DateCouponnext = bonddata[[group]]$CASHFLOWS$DATE[pos_cf+1]
  DateCouponnext = DateCouponnext[-length(DateCouponnext)]
  DateCouponnext = matrix(data = DateCouponnext,
                          nr = length(TFInfo$TFname),
                          nc = length( bonddata[[group]]$ISIN),
                          byrow = TRUE)
  
  DateCouponnext2 = bonddata[[group]]$CASHFLOWS$DATE[pos_cf+2]
  DateCouponnext2 = DateCouponnext2[-length(DateCouponnext2)]
  DateCouponnext2 = matrix(data = DateCouponnext2,
                           nr = length(TFInfo$TFname),
                           nc = length( bonddata[[group]]$ISIN),
                           byrow = TRUE)
  ##计算下两次付息金额矩阵
  Couponnext = matrix(data = bonddata[[group]]$COUPON/bonddata[[group]]$FREQUENCY,
                      nr = length(TFInfo$TFname),
                      nc = length( bonddata[[group]]$ISIN),
                      byrow = TRUE)
  Couponnext2 = Couponnext
  
  ##将付息时间超出交割时间的部分设置为0
  temp = matrix(data = TFInfo$settlementDate,
                nr = length(TFInfo$TFname),
                nc = length( bonddata[[group]]$ISIN),
                byrow = FALSE)
  
  Couponnext[which(DateCouponnext > temp)] = 0
  Couponnext2[which(DateCouponnext2 > temp)] = 0
  ##按照短期利率计算付息金额的未来价值
  FVcouponNext = Couponnext*(1 + r*as.integer(temp-DateCouponnext)/365)
  FVcouponNext2 = Couponnext2*(1 + r*as.integer(temp-DateCouponnext2)/365)
  
  FVcoupon = (FVcouponNext+FVcouponNext2)*100
  dimnames(FVcoupon) = list(TFInfo$TFname,bonddata[[group]]$ISIN)
  ##输出coupon未来价值矩阵
  FVcoupon
}

##########################################################################
##    计算以各个现券为交割券时，无套利模型下期货的理论定价
##    注意需要经过resetToday调整后计算才正确                         #####
#group:"GOV"债券分类
CalculateExpectedTFPrice = function(bonddata,group,TFInfo,QuoteBond,QuoteMoneyMarket,BondYTMBasis = 0,MoneyMarketBasis = 0)
{
  ##读入行情数据
  r = QuoteMoneyMarket$R1M[which(QuoteMoneyMarket$date == bonddata[[group]]$TODAY)]/100
  r = r + MoneyMarketBasis
  ##计算必要数据
  bonddata = InitBondPrice(bonddata,group,QuoteBond,BondYTMBasis)
  FVcoupon = CalculateFVcoupon(bonddata,group,TFInfo,r)
  daysToDelivery = matrix(data = TFInfo$settlementDate - as.Date(bonddata[[group]]$TODAY),
                          nr = length(TFInfo$TFname),
                          nc = length(bonddata[[group]]$ISIN),
                          byrow = FALSE)
  ##计算理论价格
  expectedTFPrice  = matrix(data = (bonddata[[group]]$PRICE+bonddata[[group]]$ACCRUED),
                            nr = length(TFInfo$TFname),
                            nc = length(bonddata[[group]]$ISIN),
                            byrow = TRUE)
  expectedTFPrice = (expectedTFPrice*(1 + r*daysToDelivery/365) - FVcoupon- bonddata[[group]]$accruedInterest)/bonddata[[group]]$conversionFactor
  expectedTFPrice[which(bonddata[[group]]$deliverable == FALSE)] = 0
  expectedTFPrice[which(daysToDelivery < 0)] = 0
  
  dimnames(expectedTFPrice) = list(TFInfo$TFname,bonddata[[group]]$ISIN)
  
  bonddata[[group]]$expectedTFPrice = expectedTFPrice
  
  bonddata
}
##########################################################################
##    计算以各个现券为交割券时的内部收益率IRR
##    注意需要经过resetToday调整后计算才正确                         #####
CalculateIRR = function(bonddata,group,TFInfo,QuoteBond,QuoteTF,QuoteMoneyMarket,BondYTMBasis = 0,MoneyMarketBasis = 0)
{
  ##读入行情数据
  r = QuoteMoneyMarket$R1M[which(QuoteMoneyMarket$date == bonddata[[group]]$TODAY)]/100
  r = r + MoneyMarketBasis
  bonddata = InitBondPrice(bonddata,group,QuoteBond,BondYTMBasis)
  bonddata = InitTFPrice(bonddata,group,QuoteTF)
  ##计算下两次付息时间矩阵
  n_of_cf <- summary(factor(bonddata[[group]]$CASHFLOWS$ISIN, levels = bonddata[[group]]$ISIN), maxsum = 1000)
  pos_cf <- c(0, cumsum(n_of_cf))
  DateCouponnext = bonddata[[group]]$CASHFLOWS$DATE[pos_cf+1]
  DateCouponnext = DateCouponnext[-length(DateCouponnext)]
  DateCouponnext = matrix(data = DateCouponnext,
                          nr = length(TFInfo$TFname),
                          nc = length( bonddata[[group]]$ISIN),
                          byrow = TRUE)
  
  DateCouponnext2 = bonddata[[group]]$CASHFLOWS$DATE[pos_cf+2]
  DateCouponnext2 = DateCouponnext2[-length(DateCouponnext2)]
  DateCouponnext2 = matrix(data = DateCouponnext2,
                           nr = length(TFInfo$TFname),
                           nc = length( bonddata[[group]]$ISIN),
                           byrow = TRUE)
  ##计算下两次付息金额矩阵
  Couponnext = matrix(data = bonddata[[group]]$COUPON/bonddata[[group]]$FREQUENCY,
                      nr = length(TFInfo$TFname),
                      nc = length( bonddata[[group]]$ISIN),
                      byrow = TRUE)
  Couponnext2 = Couponnext
  
  ##将付息时间超出交割时间的部分设置为0
  temp = matrix(data = TFInfo$settlementDate,
                nr = length(TFInfo$TFname),
                nc = length( bonddata[[group]]$ISIN),
                byrow = FALSE)
  Couponnext = Couponnext*100
  Couponnext2 = Couponnext2*100
  Couponnext[which(DateCouponnext > temp)] = 0
  Couponnext2[which(DateCouponnext2 > temp)] = 0
  
  ##按照短期利率计算付息金额的未来价值
  DateCouponnextInterval = as.integer(temp-DateCouponnext)
  DateCouponnext2Interval = as.integer(temp-DateCouponnext2)
  
  priceDirty    = matrix(data = (bonddata[[group]]$PRICE+bonddata[[group]]$ACCRUED),
                         nr = length(TFInfo$TFname),
                         nc = length(bonddata[[group]]$ISIN),
                         byrow = TRUE)
  daysToDelivery = matrix(data = TFInfo$settlementDate - as.Date(bonddata[[group]]$TODAY),
                          nr = length(TFInfo$TFname),
                          nc = length(bonddata[[group]]$ISIN),
                          byrow = FALSE)
  ##计算IRR
  TFPrice = matrix(data = bonddata[[group]]$TFprice,
                   nr = length(TFInfo$TFname),
                   nc = length(bonddata[[group]]$ISIN),
                   byrow = FALSE)
  TFIRR = TFPrice*bonddata[[group]]$conversionFactor + bonddata[[group]]$accruedInterest-priceDirty+Couponnext+Couponnext2
  TFIRR = TFIRR/(priceDirty*daysToDelivery/365 + (Couponnext*DateCouponnextInterval+Couponnext2*DateCouponnext2Interval)/365)
  
  TFIRR[which(bonddata[[group]]$deliverable == FALSE)] = 0
  TFIRR[which(daysToDelivery < 0)] = 0
  TFIRR[which(TFPrice == 0)] = 0
  
  dimnames(TFIRR) = list(TFInfo$TFname,bonddata[[group]]$ISIN)
  bonddata[[group]]$TFIRR = TFIRR
  bonddata
}
##########################################################################
##    计算以各个现券为交割券时的净基差NetBasis
##    注意需要经过resetToday后计算才正确                 #####
CalculateNetBasis = function(bonddata,group,TFInfo,QuoteBond,QuoteTF,QuoteMoneyMarket,BondYTMBasis = 0,MoneyMarketBasis = 0)
{
  TFPrice = CalculateExpectedTFPrice(bonddata,group,TFInfo,QuoteBond,QuoteMoneyMarket,BondYTMBasis,MoneyMarketBasis)[[group]]$expectedTFPrice
  
  bonddata = InitBondPrice(bonddata,group,QuoteBond,BondYTMBasis)
  bonddata = InitTFPrice(bonddata,group,QuoteTF)
  
  temp = matrix(data = BondInfo[[group]]$TFprice,
                nr = length(TFInfo$TFname),
                nc = length(bonddata[[group]]$ISIN),
                byrow = FALSE)
  netBasis = temp - TFPrice
  netBasis[which(TFPrice < 10)] = 0
  netBasis[which(temp == 0)] = 0
  
  bonddata[[group]]$netBasis = netBasis
  bonddata
}
######测试代码################
##bonddata = BondInfo
##group = "GOV"
#####################
FindCTD = function(bonddata,group,TFInfo,QuoteBond,QuoteTF,QuoteMoneyMarket,BondYTMBasis = 0,MoneyMarketBasis = 0)
{
  TFIRR = CalculateIRR(bonddata,group,TFInfo,QuoteBond,QuoteTF,QuoteMoneyMarket,BondYTMBasis,MoneyMarketBasis)[[group]]$TFIRR
  
  temp = TFIRR
  ##这里有个小bug，默认任何TFIRR不应该精确等于0，如果出现，这个债券不可能被选为CTD
  temp[which(temp == 0)]   = -2000
  temp[which(temp == Inf)] = -2000
  temp[which(is.na(temp))] = -2000
  maxIRR = apply(temp,1,"max")
  maxIRR = matrix(data = maxIRR,
                  nr = length(TFInfo$TFname),
                  nc = length(bonddata[[group]]$ISIN),
                  byrow = FALSE)
  
  ##这里有个小bug，默认任何两个TFIRR不应该有相等的情况。如果出现相等，将造成length(idx)==2,选不出CTD
  CTDBond = colnames(TFIRR)[(which(TFIRR - maxIRR == 0)-1) %/% length(TFInfo$TFname)+1]
  CTDTF   = rownames(TFIRR)[(which(TFIRR - maxIRR == 0)-1) %% length(TFInfo$TFname)+1]
  
  CTD = NULL
  for( i in 1: length(TFInfo$TFname))
  {
    idx = which(CTDTF == TFInfo$TFname[i])
    
    if(length(idx) == 1)
    {
      CTD[i] = CTDBond[idx]
    }
    else
    {
      CTD[i] = ""
    }
  }
  
  bonddata[[group]]$CTD = CTD
  
  bonddata
}
CalculateBPVTF = function(bonddata,group,TFInfo,QuoteBond,QuoteMoneyMarket)
{
  TFPrice_R1Mup1BP = CalculateExpectedTFPrice(bonddata,group,TFInfo,QuoteBond,QuoteMoneyMarket,MoneyMarketBasis=0.0001)[[group]]$expectedTFPrice
  TFPrice_R1Mdown1BP = CalculateExpectedTFPrice(bonddata,group,TFInfo,QuoteBond,QuoteMoneyMarket,MoneyMarketBasis=-0.0001)[[group]]$expectedTFPrice
  
  TFPrice_YTMup1BP = CalculateExpectedTFPrice(bonddata,group,TFInfo,QuoteBond,QuoteMoneyMarket,BondYTMBasis=0.0001)[[group]]$expectedTFPrice
  TFPrice_YTMdown1BP = CalculateExpectedTFPrice(bonddata,group,TFInfo,QuoteBond,QuoteMoneyMarket,BondYTMBasis=-0.0001)[[group]]$expectedTFPrice
  
  BPV_YTM = (TFPrice_YTMdown1BP - TFPrice_YTMup1BP)/2*10000
  BPV_R1M = (TFPrice_R1Mdown1BP - TFPrice_R1Mup1BP)/2*10000
  
  BPVTF_CTDslashCF = NULL
  BPVTF_YTM = NULL
  BPVTF_R1M = NULL
  for(i in 1:length(bonddata[[group]]$TFname))
  {
    if(bonddata[[group]]$CTD[i] == "")
    {
      BPVTF_CTDslashCF[i] = 0
      BPVTF_YTM[i] = 0
      BPVTF_R1M[i] = 0
    }
    else
    {
      BPVTF_CTDslashCF[i] = bonddata[[group]]$BPV[bonddata[[group]]$CTD[i]] / bonddata[[group]]$conversionFactor[bonddata[[group]]$TFname[i],bonddata[[group]]$CTD[i]]
      BPVTF_YTM[i] = BPV_YTM[bonddata[[group]]$TFname[i],bonddata[[group]]$CTD[i]]
      BPVTF_R1M[i] = BPV_R1M[bonddata[[group]]$TFname[i],bonddata[[group]]$CTD[i]]
    }
  }
  
  bonddata[[group]]$BPVTF_CTDslashCF = BPVTF_CTDslashCF
  bonddata[[group]]$BPVTF_YTM = BPVTF_YTM
  bonddata[[group]]$BPVTF_R1M = BPVTF_R1M
  
  bonddata
}


##########################################################################
##    根据TODAY信息从QuoteBond中读取需要的价格信息
##    采取根据收益率来计算净价、应计利息、全价的方式，以便符合标准的中债计算方法
InitBondPrice = function(bondinfo,group,QuoteBond,BondYTMBasis = 0)
{
  YTM = NULL
  for(i in 1:length(bondinfo[[group]]$ISIN))
  {
    print(i)
    print(bondName)
    #bondName = paste("Bond",bondinfo[[group]]$ISIN[i],sep="")
    bondName = bondinfo[[group]]$ISIN[i]
    idx      = which(QuoteBond[[bondName]]$date == bondinfo[[group]]$TODAY)
    
    if(length(idx) == 1)
    {
      YTM[i] = QuoteBond[[bondName]]$YTM[idx]
    }
    else
    {
      YTM[i] = -100
    } 
       
  }
  bondinfo[[group]]$YTM = YTM
  YTM = YTM / 100
  YTM = YTM + BondYTMBasis
  cf_p = create_cashflows_matrix(bondinfo[[group]])
  m_p = create_maturities_matrix_China(bondinfo[[group]])
  
  bondinfo[[group]]$PRICE = bond_pricesClean_China(cf_p, m_p, YTM, bondinfo[[group]]$FREQUENCY)
  bondinfo[[group]]$ACCRUED = bond_pricesDirty_China(cf_p, m_p, YTM, bondinfo[[group]]$FREQUENCY)-bondinfo[[group]]$PRICE
  
  ##将缺失数据部分设置为0
  bondinfo[[group]]$PRICE[which(YTM==-1)] = 0
  bondinfo[[group]]$ACCRUED[which(YTM==-1)] = 0
  bondinfo[[group]]$YTM[which(YTM==-1)] = 0
  
  ##设置数据精度
  bondinfo[[group]]$PRICE = round(bondinfo[[group]]$PRICE,4)
  bondinfo[[group]]$ACCRUED = round(bondinfo[[group]]$ACCRUED,4)
  bondinfo
}
## 直接读取的方法。但因为中证的应计利息计算方式与中债不同，暂不采取直接读取的方式
InitBondPrice_Old = function(bonddata,group,QuoteBond)
{
  for(i in 1:length(bonddata[[group]]$ISIN))
  {
    bondName = paste("Bond",bonddata[[group]]$ISIN[i],sep="")
    idx      = which(QuoteBond[[bondName]]$date == bonddata[[group]]$TODAY)
    length(idx)
    if(length(idx) == 1)
    {
      bonddata[[group]]$PRICE[i]    = QuoteBond[[bondName]]$priceClean[idx]
      bonddata[[group]]$ACCRUED[i]  = QuoteBond[[bondName]]$accruedInterest[idx]
    }
    else
    {
      bonddata[[group]]$PRICE[i]    = 0
      bonddata[[group]]$ACCRUED[i]  = 0
    }
    
  }
  bonddata
}
##########################################################################
##    根据TODAY信息从QuoteTF中读取需要的close price
InitTFPrice = function(bonddata,group,QuoteTF)
{
  for(i in 1:length(bonddata[[group]]$TFname))
  {
    idx = which(QuoteTF[[bonddata[[group]]$TFname[i]]]$date == bonddata[[group]]$TODAY)
    if(length(idx) == 1)
    {
      bonddata[[group]]$TFprice[i] = QuoteTF[[bonddata[[group]]$TFname[i]]]$close[idx]
    }
    else
    {
      bonddata[[group]]$TFprice[i] = 0
    }
    
  }
  bonddata
}
