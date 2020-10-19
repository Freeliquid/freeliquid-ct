
import numpy as np
import pandas as pd

from matplotlib.dates import DateFormatter, MonthLocator, YearLocator

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


def d_analize(targetCirculate = 500000, digits=6):
    panes = 3
    fig, axs = plt.subplots(panes, 1, tight_layout=True, sharex=True, squeeze=True, figsize=(30, 10))


    step = 3600*24*30
    hoursInYear = 365*24
    stop = 1*hoursInYear*3600

    integralOnStop = integral(stop, stop)

    starty = int(targetCirculate*(10**digits)/integralOnStop)
    # starty = 100
    print("starty", starty)
    df = get_data(stop, step, starty)
    df = df.set_index("x")

    df["s"] = (df.y*step).cumsum()/(10**digits)

    # aproxIntegral = (df.y*step).sum()/(10**digits)
    aproxIntegral = df.s.iloc[-1]
    print(aproxIntegral, "circulateErr", aproxIntegral-targetCirculate)
    print("integral", starty*integralOnStop/(10**digits), starty*integral(0, stop))


    df["i"] =  integral_data(stop, step) * starty / (10**digits)


    startUnixTime = 1602973840
    df["dt"] = pd.to_datetime(df.index+startUnixTime, unit="s")
    df = df.set_index("dt")

    df["perHour"] = df.y * 3600 / (10**digits)

    df = df.resample('1d').last().fillna(method='ffill')
    print(df)

    for ax in axs:
        month = MonthLocator()
        year = YearLocator()
        fmt1 = DateFormatter('%Y')
        fmt2 = DateFormatter('%b')
        ax.xaxis.set_major_locator(year)
        ax.xaxis.set_major_formatter(fmt1)
        ax.xaxis.set_minor_locator(month)
        ax.xaxis.set_minor_formatter(fmt2)



        ax.grid(True, which='major', axis='x')




    df.perHour.plot(ax=axs[0], color="red", x_compat=True)
    df.s.plot(ax=axs[1], color="red", lw=3, x_compat=True)
    df.i.plot(ax=axs[1], color="blue", x_compat=True)
    (df.i-df.s).plot(ax=axs[2], color="blue", x_compat=True)

    for ax in axs:
        ax.axhline(y=0, lw=1.0)
        ax.axvline(x=pd.to_datetime(stop+startUnixTime, unit="s"), lw=1.0)

    plt.savefig("res.png", dpi=300)
    plt.close()


if __name__ == "__main__":
    # sq_analize()
    d_analize()
