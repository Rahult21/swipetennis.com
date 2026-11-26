#!/usr/bin/env python3
"""Generate the bundled, vector-only native court guide and a shareable PDF copy.
Requires ReportLab. Every instruction describes a touch path implemented by TennisScene.
"""
from pathlib import Path
from math import atan2, cos, sin, pi
import shutil
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color, white
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'output/pdf/CourtGuide.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H, COUNT = 414, 660, 8
INK, FOREST, CREAM, SAGE = map(HexColor, ['#183C2E','#123E2D','#F7F7EF','#E6EEDC'])
YELLOW, BLUE, MINT, MUTED = map(HexColor, ['#F0EA5B','#28C5F4','#72E2B8','#5C7266'])
c = canvas.Canvas(str(OUT), pagesize=(W,H), pageCompression=1)
c.setTitle('SwipeTennis - Illustrated Court Guide')
c.setAuthor('SwipeTennis')
c.setSubject('Every on-court tap and swipe, illustrated for the native iOS app')


def label(text, x, y, size=12, color=INK, font='Helvetica', align='left'):
    c.setFillColor(color); c.setFont(font,size)
    {'left':c.drawString, 'center':c.drawCentredString, 'right':c.drawRightString}[align](x,y,text)


def para(text, x, top, width=366, size=14, leading=19, color=INK):
    style = ParagraphStyle('body',fontName='Helvetica',fontSize=size,leading=leading,textColor=color)
    p=Paragraph(text, style); _,h=p.wrap(width,1000)
    p.drawOn(c,x,top-h)
    return top-h


def page(number,title,subtitle):
    c.setFillColor(CREAM); c.rect(0,0,W,H,fill=1,stroke=0)
    label('SWIPETENNIS  /  COURT PLAYBOOK',24,628,8.5,MUTED,'Helvetica-Bold')
    label(title,24,590,28,INK,'Times-Roman')
    para(subtitle,24,568,size=13.5,leading=18)
    c.setStrokeColor(SAGE);c.setLineWidth(1);c.line(24,34,390,34)
    label('TAP  /  SWIPE  /  PLAY',24,19,8,MUTED,'Helvetica-Bold')
    label(f'{number:02d} / {COUNT:02d}',390,19,9,MUTED,align='right')
    c.bookmarkPage(f'page{number}');c.addOutlineEntry(title,f'page{number}',0,False)


def ring(x,y,color=YELLOW,r=11):
    c.setStrokeColor(color);c.setLineWidth(2)
    c.ellipse(x-r,y-r*.48,x+r,y+r*.48,stroke=1,fill=0)


def arrow(x1,y1,x2,y2,color=white,width=2.3,dashed=False):
    c.setStrokeColor(color);c.setFillColor(color);c.setLineWidth(width)
    c.setDash([3,4] if dashed else [])
    c.line(x1,y1,x2,y2);c.setDash([])
    a=atan2(y2-y1,x2-x1);q=c.beginPath();q.moveTo(x2,y2)
    for b in [a+2.6,a-2.6]:q.lineTo(x2+8*cos(b),y2+8*sin(b))
    q.close();c.drawPath(q,fill=1,stroke=0)


def hand(x,y,scale=1,tap=False):
    # Index fingertip is the exact gesture origin. Three curled fingers and a thumb read at phone size.
    c.saveState();c.translate(x,y);c.scale(scale,scale)
    c.setFillColor(white);c.setStrokeColor(HexColor('#718A7B'));c.setLineWidth(.8)
    p=c.beginPath();p.moveTo(-3,-18);p.lineTo(-3,-3);p.curveTo(-3,2,3,2,3,-3)
    p.lineTo(3,-15);p.curveTo(4,-10,9,-10,9,-15);p.curveTo(10,-12,15,-13,15,-18)
    p.curveTo(16,-15,21,-16,21,-21);p.lineTo(21,-31);p.curveTo(19,-41,2,-42,-3,-34)
    p.lineTo(-12,-23);p.curveTo(-15,-18,-10,-15,-7,-19);p.lineTo(-3,-23);p.close()
    c.drawPath(p,fill=1,stroke=1)
    if tap:
        c.setStrokeColor(white);c.setLineWidth(1.5)
        for r in [7,12]: c.circle(0,1,r,stroke=1,fill=0)
    c.restoreState()


def athlete(x,y,scale=1,opponent=False,pose='ready'):
    c.saveState();c.translate(x,y);c.scale(scale,scale)
    kit=HexColor('#F3A05C') if opponent else HexColor('#A4DAEA')
    skin=HexColor('#BB885F');c.setLineCap(1)
    c.setFillColor(Color(0,0,0,.16));c.ellipse(-14,-3,14,3,fill=1,stroke=0)
    lift=8 if pose=='jump' else 4 if pose=='hop' else 0;c.translate(0,lift)
    c.setStrokeColor(skin);c.setLineWidth(5)
    c.line(-5,15,-9,2);c.line(5,15,10,2 if pose!='land' else 11)
    c.setStrokeColor(white);c.setLineWidth(4);c.line(-10,1,-6,1);c.line(8,1 if pose!='land' else 10,12,1 if pose!='land' else 10)
    c.setFillColor(INK);c.roundRect(-8,12,16,9,2,fill=1,stroke=0)
    c.setFillColor(kit);c.roundRect(-10,20,20,17,3,fill=1,stroke=0)
    c.setStrokeColor(skin);c.setLineWidth(4)
    c.line(-9,33,-14,46 if pose in ['toss','jump'] else 26)
    wrist=(10,48) if pose=='jump' else (18,32)
    c.line(9,33,*wrist)
    c.setFillColor(skin);c.circle(0,43,5.5,fill=1,stroke=0)
    c.setFillColor(HexColor('#362B21'));c.wedge(-5.5,40,5.5,49,0,180,fill=1,stroke=0)
    c.setStrokeColor(white);c.setLineWidth(1.4);c.line(-5,44,5,44)
    c.setStrokeColor(white);c.setLineWidth(1.1)
    rx,ry=wrist;c.line(rx,ry,rx+3,ry+7);c.ellipse(rx-2,ry+6,rx+10,ry+22,fill=0,stroke=1)
    c.setLineWidth(.3)
    for i in [1,4,7]: c.line(rx+i,ry+8,rx+i,ry+20)
    for i in [10,13,16,19]:c.line(rx-1,ry+i,rx+9,ry+i)
    c.restoreState()


def ball(x,y,r=3):
    c.setFillColor(YELLOW);c.setStrokeColor(white);c.setLineWidth(.7);c.circle(x,y,r,fill=1,stroke=1)


def court(x,y,w,h):
    c.setFillColor(FOREST);c.roundRect(x,y,w,h,12,fill=1,stroke=0)
    # Short action diagrams need headroom for the opponent and raised racket.
    left=x+w*.18;right=x+w*.82;bottom=y+h*(.22 if h<100 else .13);top=y+h*(.78 if h<150 else .83)
    cw,ch=right-left,top-bottom
    c.setFillColor(HexColor('#56805A'));c.rect(left-cw*.12,bottom,cw*1.24,ch,fill=1,stroke=0)
    c.setStrokeColor(Color(1,1,1,.75));c.setLineWidth(.9)
    c.rect(left,bottom,cw,ch,stroke=1,fill=0)
    for v in [.27,.73]: c.line(left,bottom+ch*v,right,bottom+ch*v)
    c.line((left+right)/2,bottom+ch*.27,(left+right)/2,bottom+ch*.73)
    c.setLineWidth(2);c.line(left-cw*.15,bottom+ch*.5,right+cw*.15,bottom+ch*.5)
    return lambda u,v:(left+cw*u,bottom+ch*v)


def action_card(top,title,description,kind):
    x,y,w,h=24,top-234,366,234
    c.setFillColor(white);c.roundRect(x,y,w,h,14,fill=1,stroke=0)
    label(title,x+14,top-24,16,INK,'Helvetica-Bold')
    dx,dy,dw,dh=x+10,top-165,w-20,130
    p=court(dx,dy,dw,dh)
    me=p(.35,.02);other=p(.65,1)
    if kind in ['line','cross','angle','lob','body']:
        if kind=='lob': me=p(.35,-.04)
        athlete(*me,.56);athlete(*other,.44,True)
        target={'line':p(.35,.92),'cross':p(.85,.92),'angle':p(.86,.65),'lob':p(.5,.92),'body':p(.65,1)}[kind]
        arrow(me[0]+6,me[1]+15,*target,YELLOW,1.4,True)
        ball(*target,2.5)
        start=(me[0]+3,me[1]+19)
        delta={'line':(0,40),'cross':(36,40),'angle':(44,0),'lob':(0,-26),'body':(0,40)}[kind]
        offset=22 if kind=='lob' else 0
        arrow(start[0]+offset,start[1],start[0]+offset+delta[0],start[1]+delta[1],white,2.8)
        hand(*start,.65)
        ring(*me,YELLOW,11)
        arrow(*p(.7,.02),me[0]+12,me[1]+2,YELLOW,1,True)
        label('SWIPE FROM PLAYER',dx+dw-9,dy+dh-13,7,white,'Helvetica-Bold','right')
    elif kind in ['tapYellow','run']:
        me=p(.68,.02);target=p(.13,.05)
        athlete(*me,.56);athlete(*other,.44,True);ring(*target,YELLOW,13)
        arrow(me[0]-9,me[1]+5,target[0]+13,target[1]+5,YELLOW,1.4,True)
        if kind=='tapYellow':hand(*target,.7,True)
        else:
            start=p(.53,.33);end=p(.2,.33);arrow(*start,*end,white,2.8);hand(*start,.65)
    elif kind in ['approach','recover']:
        start=p(.35,.03 if kind=='approach' else .35);target=p(.4,.37 if kind=='approach' else 0)
        athlete(*start,.56);athlete(*other,.44,True)
        if kind=='approach':
            arrow(start[0],start[1]+7,*target,YELLOW,1.6,True)
            touch=p(.15,.1);arrow(*touch,touch[0]+5,touch[1]+40,white,2.8);hand(*touch,.65)
            ball(*p(.45,.72))
        else:
            ring(*target,white,13);hand(*target,.7,True)
            arrow(start[0]+4,start[1],target[0],target[1]+9,white,1.4,True)
    elif kind in ['volley','overhead']:
        me=p(.32,.38 if kind=='volley' else .25);athlete(*me,.56,pose='jump' if kind=='overhead' else 'ready')
        athlete(*other,.44,True);ring(*me,YELLOW,13)
        hand(me[0]-7,me[1]-4,.65,True)
        ball(me[0]+11,me[1]+(43 if kind=='overhead' else 20))
        arrow(other[0]-6,other[1]-6,me[0]+13,me[1]+26,YELLOW,1.4,True)
        label('AUTOMATIC CONTACT',dx+dw-10,dy+dh-15,7.5,white,'Helvetica-Bold','right')
    elif kind in ['bounce','split']:
        # A large player and fingertip explain a tap better than another tiny full court.
        c.setFillColor(FOREST);c.roundRect(dx,dy,dw,dh,12,fill=1,stroke=0)
        athlete(dx+dw*.43,dy+24,1.35,pose='hop' if kind=='bounce' else 'ready')
        hand(dx+dw*.66,dy+64,.95,True)
        ring(dx+dw*.43,dy+23,MINT if kind=='split' else white,23)
        label('TAP AT THE FAR BOUNCE' if kind=='split' else 'TAP, TAP, TAP',dx+dw/2,dy+dh-14,8.5,white,'Helvetica-Bold','center')
        if kind=='split': ball(dx+dw*.15,dy+85,5)
    para(description,x+14,top-178,w-28,size=13.5,leading=17)



GOLD=HexColor('#F5B52E')

def tile(x,top,title,copy,kind):
    w,h=178,144
    c.setFillColor(white);c.roundRect(x,top-h,w,h,11,fill=1,stroke=0)
    label(title,x+10,top-18,11.5,INK,'Helvetica-Bold')
    q=court(x+7,top-95,w-14,69)
    me=q(.30,.02);target=q(.8,.92)
    athlete(*me,.40)
    if kind in ['line','cross','angle','lob']:
        delta={'line':(0,26),'cross':(26,26),'angle':(29,0),'lob':(0,-20)}[kind]
        origin=(me[0]+3,me[1]+15)
        if kind=='line':target=q(.3,.92)
        if kind=='angle':target=q(.9,.63)
        if kind=='lob':target=q(.5,.92)
        arrow(*origin,*target,YELLOW,1,True);ball(*target,2)
        arrow(origin[0]+10,origin[1],origin[0]+10+delta[0],origin[1]+delta[1],white,2)
        hand(*origin,.46)
    elif kind=='drop':
        ring(*me,YELLOW,9);cx,cy=q(.63,.3);r=12
        c.setStrokeColor(white);c.setLineWidth(2);c.circle(cx,cy,r,fill=0,stroke=1)
        arrow(cx+r,cy+4,cx+r,cy-4,white,2);hand(cx+r,cy,.43)
        ball(*q(.78,.6),2)
    elif kind=='slice':
        start=q(-.15,.5);end=q(1,0)
        arrow(*start,*end,white,2);hand(*start,.45);ring(*end,white,7)
        arrow(me[0]+6,me[1]+14,*target,YELLOW,1,True)
    elif kind=='aim':
        blue=q(.25,.72);ring(*blue,BLUE,9);hand(*blue,.45)
        arrow(*blue,*q(.7,.72),BLUE,2)
        y=top-88
        for left,name,stop,color in [(x+12,'Speed',2,YELLOW),(x+w-55,'Spin',0,MINT)]:
            label(name,left,y-2,6,white,'Helvetica-Bold')
            start=left+19
            c.setStrokeColor(white);c.setLineWidth(.8);c.line(start,y,start+23,y)
            for tick in range(3):
                tx=start+11.5*tick;c.line(tx,y-1.6,tx,y+1.6)
            tx=start+11.5*stop
            marker=c.beginPath();marker.moveTo(tx-2,y+3);marker.lineTo(tx+2,y+3);marker.lineTo(tx,y-2);marker.close()
            c.setFillColor(color);c.drawPath(marker,fill=1,stroke=0)
    elif kind=='serve':
        hand(me[0]+10,me[1]+16,.48,True);ball(me[0]-3,me[1]+37,2.5)
        athlete(*q(.73,.1),.43,pose='jump')
    elif kind=='yellow':
        goal=q(.8,.1);ring(*goal,YELLOW,10);hand(*goal,.48,True)
        arrow(me[0]+7,me[1]+4,goal[0]-12,goal[1]+4,YELLOW,1.2,True)
    elif kind=='move':
        origin=q(.57,.33);end=q(.92,.33);arrow(*origin,*end,white,2);hand(*origin,.46)
    elif kind=='recover':
        goal=q(.5,0);ring(*goal,white,10);hand(*goal,.48,True)
    elif kind=='split':
        hand(*q(.75,.4),.5,True);ring(*me,MINT,11)
        ball(*q(.57,.76),3);ring(*q(.57,.76),MINT,7)
        label('FAR BOUNCE',x+145,top-40,6.5,white,'Helvetica-Bold','right')
    para(copy,x+10,top-102,w-20,size=10.2,leading=12)

page(1,'Tap. Move. Serve.','YOUR MOVES 1/3  -  Use the court itself. Blue aims a serve; yellow or gold receives; white recovers.')
items=[('Aim your serve','Place BLUE. Within 1 second, touch a gauge behind you: Speed on the left, Spin on the right.','aim'),
 ('Start the serve','Tap or slide to low, medium or high. Tap your side to serve. The gauges disappear.','serve'),
 ('Reach the ball','Tap YELLOW or GOLD once. The run continues without holding.','yellow'),
 ('Run in any direction','Swipe EMPTY court toward where you want to run.','move'),
 ('Recover after a shot','Tap WHITE. Reach the circle before the next split step.','recover'),
 ('Bounce / split step','Reach white. Tap anywhere as your shot bounces on the far court.','split')]
for i,(title,copy,kind) in enumerate(items):tile(24+(i%2)*188,514-(i//2)*150,title,copy,kind)
para('First serve starts fast and flat. Second starts slow with high spin. More spin adds margin and gives the receiver time.',24,64,size=10,leading=12)
c.showPage()

page(2,'Choose the next shot.','YOUR MOVES 2/3  -  Tap yellow, then finish your shot swipe before contact.')
items=[('Up: down the line','Start ON your moving player; swipe toward the net.','line'),
 ('Diagonal: crosscourt','Start ON your player; swipe forward toward the opposite side.','cross'),
 ('Sideways: short angle','Start ON your player; swipe left or right.','angle'),
 ('Down: center lob','Start ON your player; swipe straight away from the net.','lob'),
 ('Quick circle: drop','After tapping yellow, draw a small closed circle on your half.','drop'),
 ('Post diagonal: slice','Start at either NET POST. End at the opposite corner of YOUR baseline.','slice')]
for i,(title,copy,kind) in enumerate(items):tile(24+(i%2)*188,514-(i//2)*150,title,copy,kind)
para('On clean rally contact, crosscourt lands 7 in 8, line or a change of direction 4 in 5, and short angle 2 in 3. Hit behind a moving opponent to slow their next chase.',24,64,size=10,leading=12)
c.showPage()

page(3,'Combine. Then react.','YOUR MOVES 3/3  -  Hit first. Start a fresh swipe and finish it before the far bounce.')
for row,(top,title,stages) in enumerate([
 (513,'Attack: meet it, hit it, follow it',[('1 TAP GOLD','receive'),('2 SHOT + HIT','hit'),('3 SWIPE IN','approach')]),
 (291,'Baseline: recover, split, receive',[('1 TAP WHITE','recover'),('2 TIMED TAP','split'),('3 TAP YELLOW','receive')])]):
    label(title,24,top,17,INK,'Times-Roman')
    for i,(caption,kind) in enumerate(stages):
        x=24+i*125;q=court(x,top-127,116,111);me=q(.4,.05)
        athlete(*me,.48)
        label(caption,x+58,top-31,7.5,white,'Helvetica-Bold','center')
        if kind=='receive':
            goal=q(.65,.22);ring(*goal,GOLD if row==0 else YELLOW,9);hand(*goal,.48,True)
        elif kind=='hit':
            origin=(me[0]+3,me[1]+16);arrow(*origin,origin[0],origin[1]+26,white,2);hand(*origin,.45)
            ball(*q(.75,.75),2.5)
        elif kind=='approach':
            origin=q(.7,.1);end=q(.7,.42);arrow(*origin,*end,white,2);hand(*origin,.48)
            arrow(me[0],me[1]+3,*q(.4,.4),GOLD,1.3,True)
        elif kind=='recover':ring(*q(.5,0),white,10);hand(*q(.5,0),.48,True)
        else:hand(*q(.8,.22),.48,True);ring(*me,MINT,11);ball(*q(.43,.76),3);ring(*q(.43,.76),MINT,8)
    text=('After you hit, swipe forward before the far bounce. Your player plants at the bounce, or stops if the opponent volleys first. Then move to yellow for a <b>volley</b> or under a lob for an <b>overhead</b>.' if row==0 else
      'Reach white, then tap anywhere as your shot bounces across the net. You have 3 m of ball travel on either side of the bounce. Look for a mint pulse, then tap yellow.')
    para(text,24,top-140,size=12.3,leading=16)
para('<b>First serve:</b> UP returns at the server. <b>Second serve:</b> reach yellow inside the baseline and hit on the rise.',24,94,size=12,leading=16)
para('Local play: use your own half. Forward always means toward the net.',24,52,size=10,leading=12)
c.showPage()

page(4,'Gold means opportunity.','A short ball BOUNCES at least 5 metres inside your baseline. Its contact ring turns gold, thick and blinking.')
q=court(24,256,366,265)
left,bottom=q(0,0);right,_=q(1,0);_,short=q(0,5/23.77);_,net=q(0,.5)
c.setFillColor(Color(1,.71,.18,.17));c.rect(left,short,right-left,net-short,fill=1,stroke=0)
c.setStrokeColor(GOLD);c.setDash([3,3]);c.setLineWidth(1.5);c.line(left,short,right,short);c.setDash([])
label('SHORT-BALL AREA',207,net-14,9,GOLD,'Helvetica-Bold','center')
c.setStrokeColor(white);c.line(right+17,bottom,right+17,short)
c.line(right+13,bottom,right+21,bottom);c.line(right+13,short,right+21,short)
label('5 m',right+23,(bottom+short)/2,9,white,'Helvetica-Bold')
me=q(.7,0);goal=q(.3,.3);athlete(*me,.7)
c.setLineWidth(4);ring(*goal,GOLD,15);ring(*goal,GOLD,18)
hand(*goal,.7,True);arrow(me[0]-13,me[1]+8,goal[0]+15,goal[1]-3,GOLD,1.8,True)
arrow(goal[0],goal[1]+11,*q(.75,.9),GOLD,1.5,True)
label('YOUR BASELINE',207,bottom-16,8,white,'Helvetica-Bold','center')
for i,(title,copy) in enumerate([
 ('REACH','Tap gold early. You run 1.5x faster while receiving a short ball.'),
 ('CHOOSE','Select a shot while moving; arrive for a clean hit.'),
 ('FOLLOW','After contact, swipe forward to follow the ball in for +2 CP.')]):
    y=229-i*55;label(str(i+1),28,y-4,21,INK,'Times-Roman');label(title,59,y,10,INK,'Helvetica-Bold')
    para(copy,59,y-9,330,size=12,leading=16)
para('Reduce Motion keeps the gold ring steady. The short-ball rule excludes serves and out balls.',24,64,size=10.5,leading=14)
c.showPage()

page(5,'Earn Coachability Points.','Each followed opportunity earns +2. Each missed opportunity costs -1. Several rules can score on one point.')
rules=[('Short ball: follow it in','A bounce 5 m inside baseline turns the ring gold. Hit, then swipe forward.'),
 ('Behind baseline: center lob','Reach yellow; choose the straight-down lob through center.'),
 ('First serve: back at server','Tap yellow, then swipe up from your player before contact.'),
 ('Second serve: take it early','Reach yellow inside the baseline; hit after the bounce, on the rise.'),
 ('Serve wide, then crosscourt','Drag blue wide. On the return, choose a diagonal crosscourt drive.'),
 ('Change direction, follow in','After redirecting the ball, make a new forward swipe after contact.'),
 ('Recover + split for the whole point','On each baseline exchange, reach white. Tap within 3 m of the far bounce. Net approaches are exempt.')]
for i,(title,copy) in enumerate(rules):
    top=517-i*65
    c.setFillColor(white);c.roundRect(24,top-58,366,58,10,fill=1,stroke=0)
    c.setFillColor(FOREST);c.circle(45,top-22,11,fill=1,stroke=0)
    label(str(i+1),45,top-25.5,10,white,'Helvetica-Bold','center')
    label(title,66,top-18,12,INK,'Helvetica-Bold')
    para(copy,66,top-25,309,size=10.8,leading=13)
para('Rules 1-6 repeat per opportunity. Rule 7 counts once, only if there was a baseline exchange.',24,64,size=10.5,leading=13)
c.showPage()

page(6,'A partner that adapts.','Opponent choices are random. These are long-run averages, never a repeating sequence to memorize.')
label('SHORT BALLS DURING BASELINE PLAY',24,515,10,INK,'Helvetica-Bold')
for i,(level,rate) in enumerate([('EASY','About 1 in 3'),('MEDIUM','About 1 in 5'),('HARD','About 1 in 7-8')]):
    x=24+i*125;c.setFillColor(FOREST);c.roundRect(x,418,116,80,11,fill=1,stroke=0)
    label(level,x+58,475,9,white,'Helvetica-Bold','center');ring(x+58,449,GOLD,12)
    label(rate,x+58,430,10,white,'Helvetica-Bold','center')
label('WHEN YOU APPROACH THE NET',24,391,10,INK,'Helvetica-Bold')
for i,(level,copy) in enumerate([
 ('Easy','About 2/3 softer volley feeds; 1/3 pressured misses.'),
 ('Medium','About half lobs or passes; 35% softer feeds; 15% misses.'),
 ('Hard','About 3/4 lobs or passing shots; 20% softer feeds; 5% misses.')]):
    top=368-i*60;c.setFillColor(white);c.roundRect(24,top-50,366,50,9,fill=1,stroke=0)
    label(level,38,top-21,13,INK,'Helvetica-Bold');para(copy,107,top-12,270,size=12,leading=15)
label('DROP SHOTS AND SLICES',24,166,10,INK,'Helvetica-Bold')
para('Every drop shot is chased. Easy reaches 2/3, Medium 3/4 and Hard 4/5; a reached drop comes back as a deep lob. Slices travel slower and can be returned.',24,151,size=13,leading=18)
para('Inside the service box, reach wide for a diving volley or jump for a high lob. Serve returns must bounce first.',24,77,size=12,leading=16)
c.showPage()

page(7,'Read the point result.','A timed split improves placement on your next shot by 20%, up to 100%.')
c.setFillColor(FOREST);c.roundRect(24,302,366,220,15,fill=1,stroke=0)
label('Opponent won the point.',42,488,24,white,'Times-Roman')
label('GAMES  1-0       POINTS  30-30',42,466,10,YELLOW,'Helvetica-Bold')
para('Your shot landed wide. Changing direction to the shorter side was the lower-percentage play. Rally crosscourt and wait for a short ball.',42,449,326,size=12,leading=16,color=white)
label('Timed split on your last shot: 80% to 96%',42,380,12,MINT,'Helvetica-Bold')
c.setStrokeColor(MINT);c.line(42,366,372,366)
label('COACHABILITY   -1 CP',42,344,10,YELLOW,'Helvetica-Bold')
label('Missed the white recovery circle.',42,321,12,white)
label('MATCH POWERS',24,279,12,INK,'Helvetica-Bold')
para('Win two points running to earn a power. Tap the small circle at bottom right once. A check means your shot is armed.',24,266,size=12,leading=15)
for y,title,copy in [(212,'Overhead Smash','Your player gets under a high ball and jumps. A low ball sets up a lob first.'),
                     (162,'Rally Smash','Your player lines up an inside-out forehand or a two-handed backhand winner on the next return.'),
                     (112,'On Demand Ace','Drag blue if you want to pick a spot. The ace uses the blue target on your next available serve.')]:
    label(title,24,y,13,INK,'Helvetica-Bold')
    para(copy,24,y-7,360,size=11.2,leading=14)
para('After two losses, an affirmation may appear once per game. Tap to reveal the result.',24,62,size=10.3,leading=12)
c.showPage()

page(8,'Read the court.','White lines mark the court. Colored coaching cues help you choose where to move and aim.')
q=court(24,292,366,229)
left,bottom=q(0,0);right,top=q(1,1);strip=(right-left)*.85/8.23
c.setFillColor(Color(1,.58,.1,.18))
c.rect(left,bottom,strip,top-bottom,fill=1,stroke=0)
c.rect(right-strip,bottom,strip,top-bottom,fill=1,stroke=0)
label('85 cm',left+strip/2,top+13,8,YELLOW,'Helvetica-Bold','center')
label('85 cm',right-strip/2,top+13,8,YELLOW,'Helvetica-Bold','center')
athlete(*q(.5,.06),.63);athlete(*q(.5,.94),.5,True)
out=q(1.09,.16)
ring(*out,Color(1,1,0,.3),13);hand(*out,.55,True)
label('FAINT OUT-BALL TARGET',207,308,8.5,white,'Helvetica-Bold','center')
label('SIDELINE SHADING',24,268,11,INK,'Helvetica-Bold')
para('The faint yellow-orange strips run <b>85 cm inside each singles sideline</b>. They remind you to aim with margin. They are coaching overlays, not regulation lines, and appear on every surface.',24,253,size=12.5,leading=17)
label('OUT BALL: YOU CAN STILL CHASE',24,164,11,INK,'Helvetica-Bold')
para('A <b>faint yellow circle</b> remains on wide or long balls. Tap it to keep running, including just after the bounce. Red marks the out bounce for 0.3 seconds; the point result follows.',24,149,size=12.5,leading=17)
para('Settings > Contact & recovery guides controls these overlays. Chasing an out ball does not change the point or CP score.',24,64,size=10.5,leading=13)
c.showPage();c.save()
shutil.copyfile(OUT, ROOT/'SwipeTennis/CourtGuide.pdf')
print(f'Created {COUNT} illustrated pages: {OUT}')
