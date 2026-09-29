from d import *
setup_paper()
f = Flow('quote')
f.tap(*P(450, 521), wait=7.0, caption='Open the PDF', hold=1.0)
f.shot(hold=0.8, wait=0.1)
f.press(*P(162, 399), caption='Press and hold to select')
f.shot(hold=0.5, wait=0.1)
# One continuous drag of handle B onto the second line.
f.shot(hold=0.6, tap=[235, 520], caption='Drag to the end of the passage', wait=0.1)
sh('shell','input','swipe','235','520','527','537','1200'); time.sleep(1.2)
f.shot(hold=1.0)
f.tap(432, 665, wait=1.5, caption='Tap Quote to note')
f.tap(*P(200, 1845), wait=2.5, caption='Choose a note — or a new one')
f.shot(hold=2.4, caption='The quote lands with a link to its page')
