from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).with_suffix('.png')
W, H = 1450, 1360
im = Image.new('RGB', (W, H), '#F2F5F5')
d = ImageDraw.Draw(im)
REG = '/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
NAVY = '#12354F'
DEEP = '#0D293E'
RAISED = '#1D445F'
CREAM = '#FBF0D9'
MUTED = '#A9BEC9'
LINE = '#466579'
GREEN = '#3C9A72'
CORAL = '#E36B55'


def txt(x, y, value, size=20, color=CREAM, bold=False, anchor=None):
    d.text((x, y), value, font=ImageFont.truetype(BOLD if bold else REG, size), fill=color, anchor=anchor)


def rect(x, y, w, h, fill, radius=18, outline=None, line=2):
    d.rounded_rectangle((x, y, x+w, y+h), radius=radius, fill=fill, outline=outline, width=line)


def power(cx, cy, r=20, color=CREAM):
    d.arc((cx-r, cy-r, cx+r, cy+r), 315, 585, fill=color, width=5)
    d.line((cx, cy-r-4, cx, cy-4), fill=color, width=5)


def flag(x, y):
    for k, color in enumerate(('#AE1C28', '#FFFFFF', '#21468B')):
        d.rectangle((x, y+k*7, x+29, y+(k+1)*7), fill=color)
    d.rounded_rectangle((x, y, x+29, y+21), radius=3, outline=MUTED, width=1)


def country(x, y, small=False):
    flag(x, y+1)
    txt(x+40, y-1, 'Нидерланды', 19 if small else 20, CREAM, True)
    txt(x+40, y+29, 'Подключено', 15, MUTED)


def ping_value(x, y):
    txt(x, y, '43 мс', 22, CREAM, True)


def card(x, y, w, h=140):
    rect(x, y, w, h, NAVY, 24)


def circle_layout(x, y, w):
    card(x, y, w)
    if w == 160:
        d.ellipse((x+43, y+20, x+117, y+94), fill=GREEN)
        power(x+80, y+57)
        txt(x+80, y+117, 'VPN ВКЛ', 14, CREAM, True, 'mm')
    else:
        d.ellipse((x+20, y+36, x+88, y+104), fill=GREEN)
        power(x+54, y+70, 18)
        country(x+108, y+43)
        if w == 500:
            d.line((x+304, y+26, x+304, y+114), fill=LINE, width=2)
            ping_value(x+325, y+30)
            rect(x+325, y+69, 148, 42, RAISED, 12, LINE)
            txt(x+399, y+90, 'ПРОВЕРИТЬ', 14, CREAM, True, 'mm')


def bottom_layout(x, y, w):
    card(x, y, w)
    txt(x+18, y+14, 'НОНА', 15, MUTED, True)
    if w == 160:
        d.ellipse((x+122, y+19, x+132, y+29), fill=GREEN)
        rect(x+12, y+62, 136, 65, GREEN, 16)
        power(x+44, y+94, 15)
        txt(x+104, y+95, 'ВКЛ', 15, CREAM, True, 'mm')
    else:
        country(x+19, y+37)
        if w == 500:
            ping_value(x+395, y+39)
            rect(x+13, y+88, 315, 40, GREEN, 11)
            power(x+48, y+108, 11)
            txt(x+175, y+109, 'VPN ВКЛ', 14, CREAM, True, 'mm')
            rect(x+338, y+88, 149, 40, RAISED, 11, LINE)
            txt(x+412, y+109, 'ПИНГ', 14, CREAM, True, 'mm')
        else:
            rect(x+13, y+87, 294, 41, GREEN, 11)
            power(x+50, y+107, 11)
            txt(x+160, y+108, 'VPN ВКЛ', 15, CREAM, True, 'mm')


def rail_layout(x, y, w):
    card(x, y, w)
    rect(x, y, 66 if w>160 else 50, 140, GREEN, 20)
    power(x+(33 if w>160 else 25), y+70, 19 if w>160 else 15)
    if w == 160:
        txt(x+103, y+53, 'VPN', 19, CREAM, True, 'mm')
        txt(x+103, y+84, 'ВКЛ', 16, MUTED, True, 'mm')
    else:
        country(x+84, y+43)
        if w == 500:
            d.line((x+309, y+23, x+309, y+117), fill=LINE, width=2)
            ping_value(x+333, y+34)
            d.ellipse((x+425, y+43, x+474, y+92), fill=RAISED, outline=LINE, width=2)
            for bar_x, top in ((439, 68), (449, 61), (459, 54)):
                d.line((x+bar_x, y+top, x+bar_x, y+78), fill=CREAM, width=4)
            txt(x+334, y+94, 'Проверить пинг', 15, MUTED)


def toggle(x, y, w, large=False):
    tw = 112 if large else 102
    rect(x, y, tw, 50, GREEN, 25)
    d.ellipse((x+tw-45, y+5, x+tw-5, y+45), fill=CREAM)
    if large:
        txt(x+15, y+25, 'ВКЛ', 14, CREAM, True, 'lm')


def switch_layout(x, y, w):
    card(x, y, w)
    if w == 160:
        txt(x+80, y+34, 'VPN', 19, CREAM, True, 'mm')
        toggle(x+24, y+59, 160, True)
        txt(x+80, y+124, 'ПОДКЛЮЧЕНО', 11, MUTED, True, 'mm')
    elif w == 320:
        country(x+18, y+41, True)
        toggle(x+205, y+45, 320, False)
    else:
        country(x+18, y+41, True)
        d.line((x+260, y+25, x+260, y+115), fill=LINE, width=2)
        ping_value(x+280, y+31)
        rect(x+276, y+68, 96, 34, RAISED, 10, LINE)
        txt(x+324, y+85, 'ПИНГ', 13, CREAM, True, 'mm')
        d.line((x+384, y+25, x+384, y+115), fill=LINE, width=2)
        toggle(x+392, y+45, 500, False)


def tile_layout(x, y, w):
    card(x, y, w)
    if w == 160:
        rect(x+13, y+12, 134, 116, GREEN, 18)
        power(x+80, y+58, 21)
        txt(x+80, y+107, 'VPN ВКЛ', 14, CREAM, True, 'mm')
    else:
        rect(x+11, y+12, 80, 116, GREEN, 16)
        power(x+51, y+67, 19)
        txt(x+51, y+103, 'ВКЛ', 12, CREAM, True, 'mm')
        if w == 320:
            rect(x+102, y+12, 207, 116, RAISED, 16)
            country(x+119, y+43, True)
        else:
            rect(x+102, y+12, 218, 116, RAISED, 16)
            country(x+118, y+43, True)
            rect(x+331, y+12, 158, 116, RAISED, 16)
            ping_value(x+349, y+32)
            rect(x+346, y+76, 128, 36, DEEP, 10, LINE)
            txt(x+410, y+94, 'ПИНГ', 13, CREAM, True, 'mm')


# Board
TXT = NAVY
txt(60, 48, 'Виджеты Ноны', 46, TXT, True)
txt(60, 110, 'Пять схем кнопок и элементов · одна палитра', 23, '#567082')
rect(1012, 62, 20, 20, GREEN, 6); txt(1043, 60, 'VPN включён', 17, TXT)
rect(1012, 94, 20, 20, CORAL, 6); txt(1043, 92, 'VPN выключен', 17, TXT)
for x, label, desc in ((300, '1×1', 'Управление'), (490, '2×1', 'Управление + страна'), (850, '3×1', 'Управление + страна + пинг')):
    txt(x, 202, label, 23, TXT, True)
    txt(x, 232, desc, 16, '#667D88')
styles=[
    ('01', 'Круг', 'Кнопка слева', circle_layout),
    ('02', 'Панель', 'Действие снизу', bottom_layout),
    ('03', 'Рейка', 'Кнопка на всю высоту', rail_layout),
    ('04', 'Тумблер', 'Управление справа', switch_layout),
    ('05', 'Модули', 'Отдельные плитки', tile_layout),
]
for i, (number, name, desc, render) in enumerate(styles):
    y=280+i*205
    txt(60, y+18, number, 18, CORAL, True)
    txt(60, y+55, name, 29, TXT, True)
    txt(60, y+94, desc, 17, '#667D88')
    for x, w in ((300, 160), (490, 320), (850, 500)):
        render(x, y, w)
    if i<4:
        d.line((60, y+174, 1350, y+174), fill='#DCE3E5', width=2)
txt(60, 1332, 'На всех макетах VPN подключён. При отключении зелёная кнопка станет коралловой.', 17, '#667D88')
OUT.parent.mkdir(parents=True, exist_ok=True)
im.save(OUT, optimize=True)
print(OUT)
