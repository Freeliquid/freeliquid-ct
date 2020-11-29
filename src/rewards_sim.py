
import numpy as np
import pandas as pd
from datetime import datetime

from matplotlib.dates import DateFormatter, MonthLocator, YearLocator, DayLocator, RRuleLocator, WeekdayLocator, num2date

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


def d_analize(targetCirculate, days, name, stepDays, digits=8):
    panes = 2
    fig, axs = plt.subplots(panes, 1, tight_layout=True, sharex=False, squeeze=True, figsize=(30, 20))


    step = 3600*24*stepDays
    hoursInDistribution = days*24
    stop = 1*hoursInDistribution*3600

    integralOnStop = integral(stop, stop)

    starty = int(targetCirculate*(10**digits)/integralOnStop)

    print("start reward", starty, "step", step)
    df = get_data(stop, step, starty)
    df = df.set_index("x")

    df["s"] = (df.y*step).cumsum()/(10**digits)

    aproxIntegral = df.s.iloc[-1]
    print(aproxIntegral, "circulateErr", aproxIntegral-targetCirculate)
    print("integral", starty*integralOnStop/(10**digits), starty*integral(0, stop))


    df["i"] =  integral_data(stop, step) * starty / (10**digits)


    # startUnixTime = datetime.utcnow().timestamp()
    startUnixTime = 3600*24*5
    df["dt"] = pd.to_datetime(df.index+startUnixTime, unit="s")
    df = df.set_index("dt")

    # df["perHour"] = df.y * 3600 / (10**digits)

    df = df.resample(str(stepDays)+"d").last().fillna(method='ffill')
    # df = df.resample("1d").last().fillna(method='ffill')
    # print(df)

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


    prec=9
    rint = (distrib.i * (10**prec)).astype("int64")
    rint = [x*(10**(digits-prec)) for x in rint.to_list()]

    print(rint)

    print("total", functools.reduce(lambda x, y: x + y, rint))

    for ax in axs:
        ax.axhline(y=0, lw=1.0)

        # ax.axvline(x=pd.to_datetime(stop+startUnixTime, unit="s"), lw=1.0)
        ax.axvline(x=pd.to_datetime(startUnixTime, unit="s"), lw=1.0)

        ax.set_xlim(pd.to_datetime(startUnixTime, unit="s"), pd.to_datetime(stop+startUnixTime-3600*24*7, unit="s"))


        for item in ([ax.xaxis.label] + ax.get_xticklabels() + ax.get_yticklabels()):
            item.set_fontsize(32)

    axs[1].axhline(y=targetCirculate, lw=1.0)

    distrib.to_csv(name+"_distrib.csv")
    df.to_csv(name+".csv")
    plt.savefig(name+".png", dpi=300)
    plt.close()


if __name__ == "__main__":
    # sq_analize()
    d_analize(targetCirculate=450000, days=365, stepDays=7, name="lowrisk")
    d_analize(targetCirculate=400000, days=90, stepDays=2, name="hirisk")

