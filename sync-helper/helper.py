"""EPU shared-folder helper: no Discord login or bot token required."""
from pathlib import Path
import argparse,json,os,subprocess,sys,threading
if not getattr(sys,'frozen',False):sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'epu-discord'))
import shared_bridge as bridge

HOME=Path(os.environ.get('LOCALAPPDATA',str(Path.home())))/'EPUGuildSync'
def read(path):
    try:return json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError,ValueError):return {}
def connection(folder,wow):
    folder=Path(folder)
    cfg=read(folder/'connection.json')
    if not all(cfg.get(k) for k in ('helper','guild','secret','characters')) or len(cfg['secret'])<32:raise ValueError('Select the shared helper folder containing connection.json from your organiser.')
    cfg.update(folder=str(folder),wow_path=str(Path(wow)))
    return cfg
def startup(enabled):
    if sys.platform!='win32':return
    import winreg
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Run') as key:
        if enabled:
            if getattr(sys,'frozen',False):args=[sys.executable,'--background']
            else:
                pythonw=Path(sys.executable).with_name('pythonw.exe')
                args=[str(pythonw if pythonw.exists() else Path(sys.executable)),str(Path(__file__).resolve()),'--background']
            winreg.SetValueEx(key,'EPU Guild Sync Helper',0,winreg.REG_SZ,subprocess.list2cmdline(args))
        else:
            try:winreg.DeleteValue(key,'EPU Guild Sync Helper')
            except FileNotFoundError:pass
def gui(background=False):
    import tkinter as tk
    from tkinter import ttk,filedialog,messagebox
    saved=read(HOME/'config.json'); local=read(HOME/'state.json')
    root=tk.Tk(); root.title('EPU Guild Sync Helper'); root.geometry('700x510'); root.minsize(650,500)
    instance=None
    if sys.platform=='win32':
        import msvcrt
        HOME.mkdir(parents=True,exist_ok=True);instance=open(HOME/'instance.lock','a+b')
        if instance.tell()==0:instance.write(b'0');instance.flush()
        instance.seek(0)
        try:msvcrt.locking(instance.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:
            instance.close();root.withdraw();messagebox.showinfo('Already running','The EPU sync helper is already running. Use its existing window.',parent=root);root.destroy();return
    frame=ttk.Frame(root,padding=20);frame.pack(fill='both',expand=True)
    ttk.Label(frame,text='Help keep the guild connected',font=('Segoe UI',15,'bold')).pack(anchor='w')
    ttk.Label(frame,text='Use a shared OneDrive or Google Drive folder. No Discord token is needed.',wraplength=600).pack(anchor='w',pady=(5,15))
    folder=tk.StringVar(value=saved.get('folder','')); wow=tk.StringVar(value=saved.get('wow_path',r'C:\Program Files (x86)\World of Warcraft\_forever_'))
    def choose(var):
        path=filedialog.askdirectory(parent=root,initialdir=var.get() or str(Path.home()))
        if path:var.set(path)
    for label,var in [('Shared helper folder',folder),('WoW Forever folder',wow)]:
        ttk.Label(frame,text=label).pack(anchor='w');row=ttk.Frame(frame);row.pack(fill='x',pady=(3,10))
        ttk.Entry(row,textvariable=var).pack(side='left',fill='x',expand=True)
        ttk.Button(row,text='Browse…',command=lambda v=var:choose(v)).pack(side='right',padx=(8,0))
    auto=tk.BooleanVar(value=saved.get('startup',False))
    ttk.Checkbutton(frame,text='Start this helper when I sign into Windows',variable=auto).pack(anchor='w',pady=(0,8))
    status=tk.StringVar(value='Choose your folders, then select Start syncing.')
    ttk.Label(frame,textvariable=status,wraplength=600).pack(anchor='w',pady=(5,10))
    ttk.Label(frame,text='WoW imports updates at login or /reload. Your guild rank is unchanged.\nKeep this app running or minimized while you play.',wraplength=600).pack(anchor='w')
    running=False;busy=False;config=None; generation=0
    buttons=ttk.Frame(frame);buttons.pack(fill='x',pady=(15,0))
    def stop():
        nonlocal running,generation
        running=False;generation+=1;status.set('Syncing paused after the current check finishes.')
    def complete(message,token):
        nonlocal busy
        busy=False
        if token==generation and running:status.set(message)
    def work(token):
        try:message=bridge.helper_cycle(config,local);bridge.atomic(HOME/'state.json',local)
        except Exception as error:message=str(error)
        root.after(0,lambda:complete(message,token))
    def tick():
        nonlocal busy
        if running and not busy:
            busy=True;threading.Thread(target=work,args=(generation,),daemon=True).start()
        root.after(15000,tick)
    def start():
        nonlocal running,config,generation,local
        if busy:return
        try:
            new=connection(folder.get(),wow.get())
            if config and (config['helper'],config['guild'],config['folder'])!=(new['helper'],new['guild'],new['folder']):local={}
            config=new;config['startup']=auto.get();bridge.atomic(HOME/'config.json',config);startup(auto.get())
            running=True;generation+=1;status.set('Syncing…')
        except Exception as error:messagebox.showerror('Check your setup',str(error),parent=root)
    ttk.Button(buttons,text='Start syncing',command=start).pack(side='left')
    ttk.Button(buttons,text='Pause',command=stop).pack(side='left',padx=8)
    ttk.Button(buttons,text='Minimize',command=root.iconify).pack(side='right')
    root.after(100,tick)
    if saved:root.after(200,start)
    if background:root.after(300,root.iconify)
    try:root.mainloop()
    finally:
        if instance:instance.close()
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--background',action='store_true');parser.add_argument('--once',action='store_true');parser.add_argument('--config')
    args=parser.parse_args()
    if args.once:
        config=read(args.config or HOME/'config.json');local=read(HOME/'state.json')
        print(bridge.helper_cycle(config,local));bridge.atomic(HOME/'state.json',local)
    else:gui(args.background)
