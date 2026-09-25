from math import *
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

denseGrid = open("data/denseGrid copy.txt")
brickmap = open("data/brickmap copy.txt")
octree = open("data/octree copy.txt")

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

YoctreeArray = [
    [float(octree.readline())*1000 for _ in range(1000)] for _ in range(100)
]
Yoctree = []
YoctreeTop = []
YoctreeBot = []
for i in range(1000):
    val = 0
    max = YoctreeArray[0][i]
    min = YoctreeArray[0][i]
    for j in range(100):
        current = YoctreeArray[j][i]
        val += current
        if current>max : max = current
        if current<min : min = current
    val /= 100
    Yoctree.append(val)
    YoctreeTop.append(max)
    YoctreeBot.append(min)

denseGrid.close()
brickmap.close()
octree.close()

fig, ax = plt.subplots()

col1 = "C0"
col2 = "C1"
col3 = "C2"

#plt.fill_between(X, YdenseGridTop, YdenseGridBot, alpha=.5)
plt.plot(X, YdenseGrid, linewidth = 2., color = col1)
plt.plot(X, Ybrickmap, linewidth = 2., color = col2)
plt.plot(X, Yoctree, linewidth = 2., color = col3)
red_patch = mpatches.Patch(color=col1, label='Dense Grid')
blue_patch = mpatches.Patch(color=col2, label='Brickmap')
green_patch = mpatches.Patch(color=col3, label='Octree')
ax.legend(handles=[red_patch, blue_patch, green_patch])


plt.xlabel("Rotation - rad")
plt.ylabel("Temps moyen de l'echantillon - ms")
#plt.fill_between(X, YbrickmapTop, YbrickmapBot, alpha=.5)
plt.show()

fig, ax = plt.subplots()

tags = ['Dense Grid', 'Brickmap', 'Octree']
c = [32**4/1000, 24*512*32/1000, 3529*32/1000]
bar_colors = [col1, col2, col3]

bar = ax.bar(tags, c, color=bar_colors)
ax.bar_label(bar, fmt='%.f')
ax.set_ylabel('Taille - kb')
plt.show()