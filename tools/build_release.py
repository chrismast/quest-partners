"""Build the clean CurseForge candidate from an explicit file allowlist."""
from pathlib import Path
from zipfile import ZipFile,ZipInfo,ZIP_DEFLATED
import argparse,hashlib,json,re

ROOT=Path(__file__).resolve().parents[1]
FILES=('Core.lua','UI.lua','Settings.lua','Features.lua','Main.lua',
       'QuestPartners.toc','Media/Logo.tga','LICENSE.txt','README.txt','CHANGELOG.txt')
RUNTIME=FILES[:7]

def sha(data): return hashlib.sha256(data).hexdigest()

def build(source,output=None):
    source=source.resolve()
    missing=[name for name in FILES if not (source/name).is_file()]
    if missing: raise ValueError('Missing required files: '+', '.join(missing))
    toc=(source/'QuestPartners.toc').read_text(encoding='utf-8')
    match=re.search(r'^## Version:\s*(\S+)\s*$',toc,re.M)
    if not match: raise ValueError('TOC version missing')
    version=match.group(1)
    if not re.fullmatch(r'[A-Za-z0-9.\-]+',version): raise ValueError('Unsafe version identifier')
    if not re.search(r'^## Interface:\s*16001\s*$',toc,re.M): raise ValueError('Expected interface 16001')
    core=(source/'Core.lua').read_text(encoding='utf-8')
    core_version=re.search(r'C\.VERSION\s*=\s*"([^"]+)"',core)
    if not core_version or core_version.group(1)!=version: raise ValueError('Core and TOC versions differ')
    load_order=[line.strip() for line in toc.splitlines() if line.strip() and not line.startswith('#')]
    if load_order!=list(FILES[:5]): raise ValueError('Unexpected TOC load order')
    output=(output or ROOT/'upload'/f'QuestPartners-{version}-forever-alpha.zip').resolve()
    output.parent.mkdir(parents=True,exist_ok=True)
    with ZipFile(output,'w',ZIP_DEFLATED,compresslevel=9) as z:
        for name in FILES:
            info=ZipInfo('QuestPartners/'+name,date_time=(1980,1,1,0,0,0))
            info.compress_type=ZIP_DEFLATED
            info.external_attr=0o100644<<16
            z.writestr(info,(source/name).read_bytes(),compresslevel=9)
    with ZipFile(output) as z:
        assert z.testzip() is None
        assert set(z.namelist())=={'QuestPartners/'+name for name in FILES}
        assert all('..' not in name.split('/') for name in z.namelist())
        for name in FILES: assert z.read('QuestPartners/'+name)==(source/name).read_bytes()
    record={'version':version,'interface':16001,'planned_flavour':'Forever',
            'planned_file_type':'Alpha','submitted_to_curseforge':False,
            'filename':output.name,'bytes':output.stat().st_size,'sha256':sha(output.read_bytes()),
            'entry_count':len(FILES),'root':'QuestPartners/',
            'source_sha256':{name:sha((source/name).read_bytes()) for name in FILES},
            'excluded':['developer tests','audit reports','private install paths','old previews','launch documents']}
    (ROOT/'BUILD_VALIDATION.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'filename':output.name,'bytes':record['bytes'],'sha256':record['sha256'],'files':len(FILES)}))
    return record

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT/'QuestPartners')
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    build(args.source,args.output)
