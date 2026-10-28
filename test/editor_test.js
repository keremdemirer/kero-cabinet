// Exercise the real embedded editor script without a browser or dependencies.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const {execFileSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const core = fs.readFileSync(path.join(root, 'kero_cabinet/core.rb'), 'utf8');
const output = execFileSync('ruby', ['-e', "require File.expand_path('./test/geometry_test.rb'); puts JSON.generate(KeroCabinet.clone_defaults)"], {cwd:root,encoding:'utf8'});
const initial = JSON.parse(output.trim().split('\n').pop());
let script = core.slice(core.indexOf('  def dialog_html')).match(/<script>([\s\S]*?)<\/script>/)[1].replace('/* INITIAL_CONFIG */ null', JSON.stringify(initial));
const elements = {}, listeners = {};
let submitted = null, focused = null;
const radios = ['sides_full','top_bottom_full'].map(value=>({value,checked:false}));
function attr(tag,key){const m=tag.match(new RegExp('(?:^|\\s)'+key+'="([^"]*)"'));return m?m[1]:null;}
const panelStarts = ['size','layout','build','base','worktop'].map(key=>[key,core.indexOf('id="panel-'+key+'"')]).sort((a,b)=>a[1]-b[1]);
for(const match of core.matchAll(/<(?:input|select|button|div|p|span|section)[^>]*\bid="([\w-]+)"[^>]*>/g)){
 const id=match[1],tag=match[0];let value='';
 const panel=panelStarts.filter(([,offset])=>offset<match.index).pop();
 const attrs={};const parent=id==='frame_width'||id==='frame_depth'?{tagName:'DETAILS',open:false,parentElement:null}:null;
 elements[id]={id,type:attr(tag,'type'),hidden:/\bhidden\b/.test(tag),disabled:false,checked:false,min:attr(tag,'min')||'',max:attr(tag,'max')||'',dataset:{panel:attr(tag,'data-panel'),tab:attr(tag,'data-tab')},parentElement:parent,
  get value(){return value;},set value(v){value=String(v);},setAttribute(key,v){attrs[key]=v;},getAttribute(key){return attrs[key];},
  focus(){focused=id;},blur(){},scrollIntoView(){},closest(selector){if(selector==='[data-panel]'&&panel)return elements['panel-'+panel[0]];if(selector==='[data-tab]'&&this.dataset.tab)return this;return null;},
  checkValidity(){return value.trim()!==''&&Number.isFinite(Number(value))&&Number(value)>=Number(this.min)&&Number(value)<=Number(this.max);}};
}
const document={activeElement:null,getElementById(id){assert(elements[id],'Missing editor ID '+id);return elements[id];},
 addEventListener(event,handler){(listeners[event]||=[]).push(handler);},
 querySelector(selector){if(selector.startsWith('label')){const id=selector.match(/for="([^"]+)"/)[1];const m=core.match(new RegExp('<label for="'+id+'">([^<]*)'));return {textContent:m?m[1]:id};}if(selector.includes(':checked'))return radios.find(r=>r.checked);return radios.find(r=>selector.includes(r.value))||radios[0];},
 querySelectorAll(selector){return selector.includes('type=number')?Object.values(elements).filter(e=>e.type==='number'):radios;}};
const context=vm.createContext({document,window:{sketchup:{submit(raw){submitted=JSON.parse(raw);}}},console});
vm.runInContext(script,context);
assert(elements['editor-summary'].textContent.includes('1200 W'));
assert(elements['worktop-fields'].hidden);elements.worktop.checked=true;context.updateWorktop();assert(!elements['worktop-fields'].hidden);elements.worktop.checked=false;context.updateWorktop();
elements.toe_frame.checked=false;context.updateToeKick();assert(elements['timber-fields'].hidden);elements.toe_frame.checked=true;context.updateToeKick();assert(!elements['timber-fields'].hidden);
for(const key of ['size','layout','build','base','worktop']){context.showTab(key);assert(!elements['panel-'+key].hidden);assert.equal(elements['tab-'+key].getAttribute('aria-selected'),'true');}
context.showTab('size');
context.showError('Bay 1, top section is too short');assert(!elements['panel-layout'].hidden);
context.showError('Toe kick height is invalid');assert(!elements['panel-base'].hidden);
context.showTab('size');elements.panel.value='100';context.submitConfig();assert.equal(submitted,null);assert(!elements['panel-build'].hidden);assert.equal(focused,'panel');elements.panel.value='18';
context.showTab('size');context.revealInput(elements.frame_width);assert(!elements['panel-size'].hidden);assert(elements.frame_width.parentElement.open);
context.submitConfig();assert(submitted);for(const key of Object.keys(initial)){assert.deepStrictEqual(submitted[key],initial[key],'Setting lost or changed: '+key);}
context.layoutPreset(0,'three');assert(elements['editor-summary'].textContent.includes('2 bays'));assert(elements.bays.innerHTML.includes('Middle'));
context.addBay();assert(elements['editor-summary'].textContent.includes('3 bays'));
context.showTab('size');listeners.keydown[0]({target:elements['tab-size'],key:'ArrowRight',preventDefault(){}});assert(!elements['panel-layout'].hidden);assert.equal(focused,'tab-layout');
console.log('Editor tabs, keyboard navigation, hidden-field validation, advanced reveal, summaries and all saved defaults passed.');

elements.base_type.value='none';context.updateToeKick();assert(elements['timber-base'].hidden);assert(elements['caster-fields'].hidden);assert(elements.toe.disabled);
elements.base_type.value='casters';context.updateToeKick();assert(elements['timber-base'].hidden);assert(!elements['caster-fields'].hidden);assert(!elements.caster_height.disabled);elements.caster_height.value='120';elements.caster_diameter.value='80';context.submitConfig();assert.equal(submitted.base_type,'casters');assert.equal(submitted.caster_height,120);
context.showError('Worktop material is invalid');assert(!elements['panel-worktop'].hidden);context.showError('Caster plates do not fit');assert(!elements['panel-base'].hidden);console.log('Base modes, conditional fields, caster settings and separate Worktop tab passed.');

// Drawer-specific organizer edits, deep-copy behavior and saved settings.
context.changeBay(0,'kind','drawer');context.changeBay(0,'drawers','2');
assert(elements.bays.innerHTML.includes('Drawer organizers'));
assert(elements.bays.innerHTML.includes('Drawer 2'));
context.changeOrganizer(0,-1,0,'type','panels');
context.changeOrganizer(0,-1,0,'columns','1 2 1');
context.changeOrganizer(0,-1,0,'height','60');
context.copyOrganizer(0,-1,0);
context.changeOrganizer(0,-1,1,'columns','1 1');
assert.equal(context.organizerAt(0,-1,0).columns,'1 2 1');
assert.equal(context.organizerAt(0,-1,1).columns,'1 1');
context.changeOrganizer(0,-1,1,'type','gridfinity');
context.addOrganizerBin(0,-1,1);context.addOrganizerBin(0,-1,1);
context.changeOrganizerBin(0,-1,1,0,'w','2');
context.removeOrganizerBin(0,-1,1,1);
let previewRequest;
context.window.sketchup.organizer_preview=raw=>{previewRequest=JSON.parse(raw);};
context.requestOrganizerPreview();assert(previewRequest);
assert.equal(previewRequest.config.bays[0].organizers[0].height,60);
assert.equal(previewRequest.config.bays[0].organizers[1].bins[0].w,2);
const plan={type:'gridfinity',width:500,depth:400,height:100,columns:11,rows:9,origin:[19,11],grid_width:462,grid_depth:378,edge_gaps:[19,19,11,11],max_height_units:12,bins:[{px:19.25,py:11.25,width:83.5,depth:41.5}],pieces:[]};
context.receiveOrganizerPreview([{key:'0:-1:1',plan}],previewRequest.version);
assert(elements.bays.innerHTML.includes('11 x 9 cells'));
assert(elements.bays.innerHTML.includes('Organizer top view'));
context.changeOrganizer(0,-1,1,'align','front_left');
context.receiveOrganizerPreview([{key:'0:-1:1',plan}],previewRequest.version);
assert(!elements.bays.innerHTML.includes('11 x 9 cells'),'Stale preview was accepted');
context.submitConfig();assert.equal(submitted.bays[0].organizers[0].type,'panels');
assert.equal(submitted.bays[0].organizers[1].type,'gridfinity');
context.layoutPreset(0,'drawer');context.changeOrganizer(0,0,0,'type','panels');
context.submitConfig();assert.equal(submitted.bays[0].sections[0].organizers[0].type,'panels');
context.showError('Gridfinity bin 1 is outside the grid');assert(!elements['panel-layout'].hidden);
console.log('Per-drawer panel/Gridfinity settings, fit preview, stale-response rejection and stacked serialization passed.');

const interiorOutput=execFileSync('ruby',['-e',"require File.expand_path('./test/geometry_test.rb'); puts JSON.generate(KeroCabinet.interior_view_html([{'label'=>'Bay 1 - doors','fronts'=>['Bay 1 door 1','Bay 1 door 2']},{'label'=>'Bay 2 - drawer 1','fronts'=>['Bay 2 drawer front 1']}],[],false))"],{cwd:root,encoding:'utf8'});
const interiorHtml=JSON.parse(interiorOutput.trim().split('\n').pop());
const viewElements={groups:{innerHTML:''},error:{textContent:''}};
let viewRequest;
const viewContext=vm.createContext({document:{getElementById:id=>viewElements[id]},window:{sketchup:{interior:raw=>{viewRequest=JSON.parse(raw);}}}});
vm.runInContext(interiorHtml.match(/<script>([\s\S]*?)<\/script>/)[1],viewContext);
assert(viewElements.groups.innerHTML.includes('Bay 2 - drawer 1'));
viewContext.setInterior(1,true);assert.deepStrictEqual(viewRequest,{index:1,show:true});
viewContext.setAll(false);assert.deepStrictEqual(viewRequest,{index:'all',show:false});
viewContext.renderInterior({groups:[{label:'Bay 1',fronts:['a','b']}],hidden:['a','b']});assert(viewElements.groups.innerHTML.includes('checked'));
viewContext.interiorError('Unavailable');assert.equal(viewElements.error.textContent,'Unavailable');
console.log('Live interior switches, restore-all action and panel state rendering passed.');
