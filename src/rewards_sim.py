
import numpy as np
import pandas as pd
from datetime import datetime

from matplotlib.dates import DateFormatter, MonthLocator, YearLocator, DayLocator, RRuleLocator, WeekdayLocator, num2date
from matplotlib.ticker import IndexLocator, ScalarFormatter

import functools

import math

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def sqrt(y):
    # return math.sqrt(y), 0
    cnt = 0
    if y > 3:
        z = y
        x = int(y // 2 + 1)
        while x < z:
            z = x
            x = int((int(y // x) + x) // 2)
            cnt += 1

    elif y != 0:
        z = 1
    else:
        z =0
    return z, cnt



def get_sq_data(stop, step):
    d = []
    for x in range(0, stop, step):
        sq, cnt = sqrt(x)
        d.append([x, cnt, sq, math.sqrt(x)])
    return pd.DataFrame(d, columns=["x", "cnt", "y", "yo"])

def sq_analize():
    panes = 3
    fig, axs = plt.subplots(panes, 1, tight_layout=True, sharex=True, squeeze=True, figsize=(30, 10))

    step = 1000
    df = get_sq_data(15*365*24*step, step)
    df = df.set_index("x")
    print(df)

    df.y.plot(ax=axs[0], color="red")
    df.yo.plot(ax=axs[0], color="blue")
    df.cnt.plot(ax=axs[1], color="red")
    (df.yo-df.y).plot(ax=axs[2], color="blue")

    plt.savefig("res.png", dpi=300)
    plt.close()


def f(x, sss):
    sq, _ = sqrt(x)
    return (sss-sq) ** 2


def get_data(stop, step, starty):
    sss, _ = sqrt(stop)
    start = f(0, sss)
    d = []
    for x in range(0, stop, step):
        d.append([x, starty*f(x, sss)//start])
    return pd.DataFrame(d, columns=["x", "y"])

def integral_core(x, sss, start):
    sqrtx = math.sqrt(x)
    return x * (6 * sss*sss - 8*sss*sqrtx + 3 * x) / (6 * start)

def integral(x, stop):
    sss = math.sqrt(stop)
    start = f(0, sss)
    return integral_core(x, sss, start)

def integral_data(stop, step):
    sss = math.sqrt(stop)
    start = f(0, sss)

    d = []
    for x in range(0, stop, step):
        d.append([x, integral_core(x, sss, start)])
    df = pd.DataFrame(d, columns=["x", "i"]).set_index("x")
    return df.i

class DateFormatterEx (DateFormatter):
    def __init__(self):
        super().__init__("%m")

    def __call__(self, x, pos=0):
        if x == 0:
            raise ValueError('DateFormatter found a value of x=0, which is '
                             'an illegal date; this usually occurs because '
                             'you have not informed the axis that it is '
                             'plotting dates, e.g., with ax.xaxis_date()')
        monthid = num2date(x, self.tz).strftime(self.fmt)
        return "month "+str(int(monthid)-1)


STARTUNIXTIME = 3600*24*5
# STARTUNIXTIME = datetime.utcnow().timestamp()

def applyTicks(axs, days, stop):
    for ax in axs:
        month = MonthLocator()
        year = YearLocator()
        day = DayLocator()
        day2 = DayLocator(bymonthday=1)
        # rrule = RRuleLocator()
        if days < 100:
            fmt1 = DateFormatter('week %W')
            week = WeekdayLocator()
            ax.xaxis.set_major_locator(week)
            ax.xaxis.set_major_formatter(fmt1)
        else:
            fmt2 = DateFormatterEx()
            ax.xaxis.set_major_locator(day2)
            ax.xaxis.set_major_formatter(fmt2)


        ax.xaxis.set_minor_locator(day)
        # ax.xaxis.set_minor_formatter(fmt2)

    for ax in axs:
        ax.axhline(y=0, lw=1.0)

        # ax.axvline(x=pd.to_datetime(stop+STARTUNIXTIME, unit="s"), lw=1.0)
        ax.axvline(x=pd.to_datetime(STARTUNIXTIME, unit="s"), lw=1.0)

        ax.set_xlim(pd.to_datetime(STARTUNIXTIME, unit="s"), pd.to_datetime(stop+STARTUNIXTIME-3600*24*7, unit="s"))


        for item in ([ax.xaxis.label] + ax.get_xticklabels() + ax.get_yticklabels()):
            item.set_fontsize(32)
def gen_ct_data(distrib, digits):
    prec=9
    rint = (distrib * (10**prec)).astype("int64")
    rint = [x*(10**(digits-prec)) for x in rint.to_list()]
    return rint

DIGITS=8
DIGITS=18

def d_analize(targetCirculate, days, name, stepDays, digits=DIGITS):
    panes = 2
    fig, axs = plt.subplots(panes, 1, tight_layout=True, sharex=False, squeeze=True, figsize=(30, 20))


    step = 3600*24*stepDays
    hoursInDistribution = days*24
    stop = 1*hoursInDistribution*3600

    integralOnStop = integral(stop, stop)

    starty = int(targetCirculate*(10**digits)/integralOnStop)

    print("start reward", starty, "step", step, "integralOnStop", integralOnStop)
    df = get_data(stop, step, starty)
    df = df.set_index("x")

    df["s"] = (df.y*step).cumsum()/(10**digits)

    aproxIntegral = df.s.iloc[-1]
    print(aproxIntegral, "circulateErr", aproxIntegral-targetCirculate)
    print("integral", starty*integralOnStop/(10**digits), starty*integral(0, stop))


    df["i"] =  integral_data(stop, step) * starty / (10**digits)


    df["dt"] = pd.to_datetime(df.index+STARTUNIXTIME, unit="s")
    df = df.set_index("dt")

    # df["perHour"] = df.y * 3600 / (10**digits)

    df = df.resample(str(stepDays)+"d").last().fillna(method='ffill')
    # df = df.resample("1d").last().fillna(method='ffill')
    # print(df)

    x_compat=True

    distrib = pd.DataFrame(df.i.diff().shift(-1).fillna(targetCirculate-df.i.iloc[-1]))
    distrib["ut"] = distrib.index.astype("int")//1000000000
    # distrib["perHour"] = distrib.i / (stepDays*24)
    df["perHour"] = distrib.i / (stepDays*24)
    # print(distrib)
    # distrib["rr"] = (distrib.i * (10**digits)).astype("int64")

    df.perHour.plot(ax=axs[0], color="red", lw=9, x_compat=x_compat)
    # df.s.plot(ax=axs[1], color="red", lw=3, x_compat=x_compat)
    df.i.plot(ax=axs[1], color="blue", lw=9, x_compat=x_compat)
    if panes > 2:
        (df.i-df.s).plot(ax=axs[2], color="blue", x_compat=x_compat)

    df.to_csv(name+".csv")

    rint = gen_ct_data(distrib.i, digits)

    print(rint)

    print("total", functools.reduce(lambda x, y: x + y, rint))

    applyTicks(axs, days, stop)

    axs[1].axhline(y=targetCirculate, lw=1.0)

    distrib.to_csv(name+"_distrib.csv")
    df.to_csv(name+".csv")
    plt.savefig(name+".png", dpi=300)
    plt.close()

    return df["perHour"], distrib

def draw_combined(datas, names):

    stop = max(map(lambda distr: distr.index.max(), datas))
    index = pd.date_range(start=pd.to_datetime(STARTUNIXTIME, unit="s"),
                          end=stop, freq="1d")
    indexh = pd.date_range(start=pd.to_datetime(STARTUNIXTIME, unit="s"),
                          end=stop, freq="1d")

    df = pd.DataFrame(index=index)
    total = pd.Series(data=150000.0, index=indexh)
    dfh = pd.DataFrame(index=indexh)


    for distr, name in zip(datas, names):
        df[name] = distr.resample("1d").last().fillna(method='ffill')
        # total += df[name].resample("1h").last().fillna(method='ffill').fillna(0.0).cumsum()
        # dfh[name] = df[name].resample("1h").last().fillna(method='ffill').fillna(0.0).cumsum()
        total += df[name].resample("1h").last().fillna(method='ffill').fillna(0.0).cumsum()
        dfh[name] = df[name].resample("1h").last().fillna(method='ffill').fillna(0.0).cumsum()


    x_compat = True
    # print(df)

    panes = 2
    fig, axs = plt.subplots(panes, 1, tight_layout=True, sharex=True, squeeze=True, figsize=(30, 20))

    applyTicks(axs, 900, stop.timestamp())



    df.plot(ax=axs[0], lw=9, x_compat=x_compat)

    dfh.plot(ax=axs[1], lw=9, x_compat=x_compat)
    total.plot(ax=axs[1], lw=9, x_compat=x_compat)

    axs[1].axhline(y=1000000, lw=1.0, color="black")
    axs[1].axhline(y=450000, lw=1.0, color="black")
    axs[1].axhline(y=400000, lw=1.0, color="black")

    loc = IndexLocator(100000, 100000)
    axs[1].yaxis.set_major_locator(loc)
    formater = ScalarFormatter(useOffset=False)
    formater.set_powerlimits((-10,10))
    axs[1].yaxis.set_major_formatter(formater)

    plt.savefig("combo.png", dpi=300)
    plt.close()

def adjust(distrib, adjVal, days=90, stepDays=2, digits=DIGITS):
    print(distrib.i)
    print(len(distrib))

    totalToAdj=len(distrib) * adjVal;

    orgPerHour, adjDistrib = d_analize(targetCirculate=totalToAdj, days=days, stepDays=stepDays, name="adjust_sub")
    # print(adjDistrib)


    distrib.i += adjVal
    distrib.i -= adjDistrib.i
    # print(distrib)
    print(distrib.i.sum())


    hoursInDistribution = days*24
    stop = 1*hoursInDistribution*3600


    index = pd.date_range(start=orgPerHour.index.min(),
                          periods=len(orgPerHour)+1, freq=str(stepDays)+"d")


    df = pd.DataFrame(index=index);
    df["perHour"] = (distrib.i / (stepDays*24))
    df["i"] = (df["perHour"].shift(1)*24*stepDays).cumsum().fillna(0)
    df["perHour"].fillna(0, inplace=True)


    df.to_csv("df.csv")

    x_compat=True
    panes = 2
    fig, axs = plt.subplots(panes, 1, tight_layout=True, sharex=True, squeeze=True, figsize=(30, 20))
    df.perHour.plot(ax=axs[0], color="red", lw=9, x_compat=x_compat)
    df.i.plot(ax=axs[1], color="blue", lw=9, x_compat=x_compat)

    applyTicks(axs, days, stop)

    plt.savefig("adjusted.png", dpi=300)
    plt.close()


    rint = gen_ct_data(distrib.i, digits)
    print(rint)
    return df["perHour"]


if __name__ == "__main__":
    lowriskDays = 7
    hiriskDays = 2
    lowrisk, _ = d_analize(targetCirculate=450000, days=365, stepDays=lowriskDays, name="lowrisk")
    hirisk, distrib = d_analize(targetCirculate=400000, days=90, stepDays=hiriskDays, name="hirisk")
    hiriskAdjusted = adjust(distrib, 4500, days=90, stepDays=hiriskDays)

    draw_combined([lowrisk, hiriskAdjusted], ["lowrisk", "hirisk"])


