import re,sys,subprocess
# reads check output lines from stdin, replaces ':=' with '=' at reported lines for inference errors
fixed=0
for line in sys.stdin:
    if "Cannot infer the type" not in line and "inferred from a Variant" not in line:
        continue
    m=re.search(r"res://([^:]+):(\d+)",line)
    if not m: continue
    path,ln=m.group(1),int(m.group(2))
    L=open(path).read().split("\n")
    if " := " in L[ln-1]:
        L[ln-1]=L[ln-1].replace(" := "," = ",1)
        open(path,"w").write("\n".join(L)); fixed+=1
print("fixed",fixed)
