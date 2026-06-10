from math import *
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

denseGrid = open("data/denseGrid copy.txt")
brickmap = open("data/brickmap copy.txt")

X = [2*pi*i/1000 for i in range(1000)]
YdenseGridArray = [
    [float(denseGrid.readline())*1000 for _ in range(1000)] for _ in range(100)
]
YdenseGrid = []
YdenseGridTop = []
YdenseGridBot = []
for i in range(1000):
    val = 0
    max = YdenseGridArray[0][i]
    min = YdenseGridArray[0][i]
    for j in range(100):
        current = YdenseGridArray[j][i]
        val += current
        if current>max : max = current
        if current<min : min = current
    val /= 100
    YdenseGrid.append(val)
    YdenseGridTop.append(max)
    YdenseGridBot.append(min)

YbrickmapArray = [
    [float(brickmap.readline())*1000 for _ in range(1000)] for _ in range(100)
]
Ybrickmap = []
YbrickmapTop = []
YbrickmapBot = []
for i in range(1000):
    val = 0
    max = YbrickmapArray[0][i]
    min = YbrickmapArray[0][i]
    for j in range(100):
        current = YbrickmapArray[j][i]
        val += current
        if current>max : max = current
        if current<min : min = current
    val /= 100
    Ybrickmap.append(val)
    YbrickmapTop.append(max)
    YbrickmapBot.append(min)

denseGrid.close()
brickmap.close()

fig, ax = plt.subplots()

col1 = "C0"
col2 = "C1"

#plt.fill_between(X, YdenseGridTop, YdenseGridBot, alpha=.5)
plt.plot(X, YdenseGrid, linewidth = 2., color = col1)
plt.plot(X, Ybrickmap, linewidth = 2., color = col2)
red_patch = mpatches.Patch(color=col1, label='Dense Grid')
blue_patch = mpatches.Patch(color=col2, label='Brickmap')
ax.legend(handles=[red_patch, blue_patch])


plt.xlabel("Rotation - rad")
plt.ylabel("Temps moyen de l'echantillon - ms")
#plt.fill_between(X, YbrickmapTop, YbrickmapBot, alpha=.5)
plt.show()