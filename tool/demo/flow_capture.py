from d import *
fresh()
f = Flow('capture')
f.shot(hold=1.4, caption='Tap New note')
f.tap(*P(724, 1702), wait=1.4)
f.tap(*P(200, 290), wait=0.8, caption='Give it a title')
for chunk in ['Reading', ' group', ' - week 3']:
    f.type(chunk, wait=0.9); f.shot(hold=0.45, wait=0.1)
f.tap(*P(300, 380), wait=0.8, caption='…and just start writing')
for chunk in ['Transformers replace ', 'recurrence with ', 'self-attention.']:
    f.type(chunk, wait=0.9); f.shot(hold=0.45, wait=0.1)
f.shot(hold=1.2, caption='It saves as you type')
f.key(4, wait=0.6)   # hide keyboard
f.key(4, wait=1.2)   # back to the list
f.shot(hold=2.2, caption='Back on the list, already saved')
