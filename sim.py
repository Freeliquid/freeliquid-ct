
import numpy as np
import pandas as pd

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


supply = 0
balance = {}

lastUpdateTime = 0
rewardRate = 2
rewardPerTokenStored = 0
userRewardPerTokenPaid = {}
rewards = {}


def rewardPerToken(curTime):
    if supply == 0:
        return rewardPerTokenStored

    dt = curTime - lastUpdateTime

    rptd = (dt * rewardRate) / supply
    return rewardPerTokenStored + rptd


def updateReward(curTime):
    global rewardPerTokenStored
    global lastUpdateTime
    rewardPerTokenStored = rewardPerToken(curTime)
    lastUpdateTime = curTime


def stake(curTime, account, amnt):
    updateRewardAccount(curTime, account)
    balance[account] = balance.get(account, 0) + amnt
    global supply
    supply += amnt

def unstake(curTime, account, amnt):
    updateRewardAccount(curTime, account)
    balance[account] = balance.get(account, 0) - amnt
    global supply
    supply -= amnt


def earned(curTime, account):
    rewardChange = rewardPerToken(curTime) - userRewardPerTokenPaid.get(account, 0)
    return balance.get(account, 0) * rewardChange + rewards.get(account, 0)



def updateRewardAccount(curTime, account):
    updateReward(curTime)
    rewards[account] = earned(curTime, account)
    userRewardPerTokenPaid[account] = rewardPerTokenStored



def loop(stopTime, upd, stakes, newaccounts={}):

    curTime = 0
    accounts = set()

    hist = []

    while curTime < stopTime:

        naa = newaccounts.get(curTime)
        if naa is not None:
            for na in naa:
                accounts.add(na[0])
                stake(curTime, na[0], na[1])

        e = {}
        for a in accounts:
            if upd.get(a, False):
                if upd.get(a, False) == 1 or curTime % upd.get(a, False) == 0:
                    # updateRewardAccount(curTime, a)
                    stake(curTime, a, 0.0001)
            s = stakes.get(a)
            if s is not None:
                (time, amt) = s
                if time == curTime:
                    if amt > 0:
                        stake(curTime, a, amt)
                    else:
                        unstake(curTime, a, -amt)

            e[str(a)] = earned(curTime, a)

            if curTime == 200:
                unstake(curTime, a, 100)

        hist.append(e)

        curTime += 1

    return hist


if __name__ == "__main__":

    panes = 1
    fig, axs = plt.subplots(panes, 1, tight_layout=True, sharex=True, squeeze=True, figsize=(30, 10))

    stopTime = 30

    newaccounts = {0:[(1, 100), (2, 100), (3, 150), (4, 100)]}

    newaccounts[10] = [(5, 100)]
    newaccounts[15] = [(5, 800)]
    newaccounts[20] = [(6, 1000)]
    newaccounts[23] = [(2, 1000)]

    df1 = pd.DataFrame(loop(stopTime, {}, {}))
    stakes = {1:(3, 150), 2:(5, 250), 3:(6, -150)}
    df2 = pd.DataFrame(loop(stopTime, {1:True, 2:2, 3:3}, stakes, newaccounts))
    print(df2)
    print(df2.sum(axis=1).diff())
    for c in df2.columns:
        df1["upd_"+str(c)] = df2[c]
    df2.plot()
    # df1.plot(ax=axs[0])
    # df2.plot(ax=axs[1])

    plt.savefig("res.png", dpi=300)
    plt.close()


