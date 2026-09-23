import React, { useEffect, useMemo, useRef, useState } from "react";
import { Routes, Route, Link, useNavigate } from "react-router-dom";
import { supabase } from "./supabase";
import { QRCodeCanvas } from "qrcode.react";
import { Html5QrcodeScanner } from "html5-qrcode";

const BRAND = {
  college: "Sahyadri College of Engineering & Management",
  location: "Mangaluru, Karnataka",
  event: "Avirbhava'26",
  association: "CLOUDS Association",
};

function useStaff() {
  const [staff, setStaffState] = useState(() => {
    try { return JSON.parse(localStorage.getItem("clouds_staff") || "null"); }
    catch { return null; }
  });
  const setStaff = (value) => {
    if (value) localStorage.setItem("clouds_staff", JSON.stringify(value));
    else localStorage.removeItem("clouds_staff");
    setStaffState(value);
  };
  return [staff, setStaff];
}

function Shell({ children }) {
  return (
    <div className="app">
      <header className="topbar">
        <Link to="/" className="header-brand">
          <img src="/branding/sahyadri.png" alt="Sahyadri College" className="header-sahyadri" />
          <div className="header-divider" />
          <img src="/branding/clouds.png" alt="CLOUDS" className="header-clouds" />
          <div className="header-copy">
            <strong>CLOUDS</strong>
            <span>Avirbhava'26 · FoodPass</span>
          </div>
        </Link>
      </header>
      <main>{children}</main>
      <footer>
        <div className="footer-line">
          <span>{BRAND.college} · {BRAND.location}</span>
          <span>{BRAND.association}</span>
        </div>
        <div className="footer-credit">made by <b>SAMYAM PAI</b></div>
      </footer>
    </div>
  );
}

function Loading({ text = "Please wait…" }) {
  return <div className="loading"><div className="spinner" /><span>{text}</span></div>;
}

function Home() {
  return (
    <Shell>
      <section className="home">
        <div className="brand-strip">
          <img src="/branding/sahyadri.png" alt="Sahyadri" />
          <div>
            <span>SAHYADRI COLLEGE OF ENGINEERING & MANAGEMENT</span>
            <small>Mangaluru, Karnataka</small>
          </div>
          <div className="brand-strip-divider" />
          <img src="/branding/clouds.png" alt="CLOUDS" />
          <div>
            <span>CLOUDS ASSOCIATION</span>
            <small>Computer Science & Engineering</small>
          </div>
        </div>

        <div className="hero">
          <div className="hero-copy">
            <div className="eyebrow">CLOUDS ASSOCIATION · PRESENTS</div>
            <h1>Avirbhava'26<br /><span></span></h1>
            <p>
              Your digital food pass for the event. Register with your USN,
              check your approval, and show your QR code when food is served.
            </p>
            <div className="hero-actions">
              <Link to="/register" className="btn primary">Register <span>→</span></Link>
              <Link to="/status" className="btn outline">Check Status</Link>
            </div>
          </div>

          <div className="event-panel">
            <div className="panel-top">
              <span>FOODPASS</span>
              <span>2026</span>
            </div>
            <div className="panel-rule" />
            <div className="panel-body">
              <img src="/branding/clouds.png" alt="" />
              <div>
                <small>EVENT</small>
                <h2>Avirbhava'26</h2>
                <p>Sahyadri College of Engineering & Management</p>
              </div>
            </div>
            <div className="panel-bottom">
              <span>REGISTER</span><i>—</i><span>APPROVE</span><i>—</i><span>SCAN</span>
            </div>
          </div>
        </div>

        <div className="home-note">
          <span>Digital food verification</span>
          <span>•</span>
          <span>One QR · One redemption</span>
        </div>
      </section>
    </Shell>
  );
}

function Register() {
  const [form, setForm] = useState({ name: "", usn: "", year: "", section: "", food: "" });
  const USN_RE = /^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$/i;
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setMsg(null);
    const { data, error } = await supabase.rpc("register_student", {
      p_full_name: form.name.trim(),
      p_section: form.section,
      p_year: Number(form.year),
      p_usn: form.usn.trim().toUpperCase(),
      p_food_preference: form.food,
    });
    setBusy(false);
    if (error) setMsg({ bad: true, text: error.message });
    else if (!data?.success) setMsg({ bad: true, text: data?.message || "Registration failed." });
    else {
      setMsg({ bad: false, text: "Registration successful. Check your status later using your USN." });
      setForm({ name: "", usn: "", year: "", section: "", food: "" });
    }
  };

  return <Shell><div className="page">
    <Link to="/" className="back">← FoodPass</Link>
    <div className="form-card">
      <div className="eyebrow">01 / REGISTER</div>
      <h2>Get your FoodPass</h2>
      <p className="muted">Use the same name and USN used by the college.</p>
      <form onSubmit={submit}>
        <label>Full name<input required value={form.name} onChange={e => setForm({...form,name:e.target.value})} placeholder="Your full name" /></label>
        <label>USN<input required value={form.usn} onChange={e => setForm({...form,usn:e.target.value.toUpperCase()})} placeholder="4SF24CS001" /></label>
        <div className="two-fields"><label>Year<select required value={form.year} onChange={e => setForm({...form,year:e.target.value})}>
          <option value="">Select year</option><option value="1">1st Year</option><option value="2">2nd Year</option><option value="3">3rd Year</option><option value="4">4th Year</option>
        </select></label><label>Section<select required value={form.section} onChange={e => setForm({...form,section:e.target.value})}><option value="">Select section</option><option value="A">A</option><option value="B">B</option><option value="C">C</option><option value="D">D</option></select></label><label>Food Preference<select required value={form.food} onChange={e=>setForm({...form,food:e.target.value})}><option value="">Select preference</option><option value="veg">Veg</option><option value="non-veg">Non-Veg</option></select></label></div>
        {msg && <div className={`alert ${msg.bad ? "bad" : "good"}`}>{msg.text}</div>}
        <button className="btn primary full" disabled={busy}>{busy ? "Submitting…" : "Submit Registration"}</button>
      </form>
      <div className="form-foot">Already registered? <Link to="/status">Check your status →</Link></div>
    </div>
  </div></Shell>;
}

function Status() {
  const [usn,setUsn]=useState(""); const [busy,setBusy]=useState(false); const [data,setData]=useState(null);
  const check=async e=>{
    e.preventDefault(); setBusy(true); setData(null);
    const {data,error}=await supabase.rpc("get_student_status",{p_usn:usn.trim().toUpperCase()});
    setBusy(false); setData(error?{success:false,message:error.message}:data);
  };
  return <Shell><div className="page">
    <Link to="/" className="back">← FoodPass</Link>
    <div className="form-card">
      <div className="eyebrow">02 / STATUS</div>
      <h2>Check your FoodPass</h2>
      <p className="muted">Enter your USN. That's all.</p>
      <form onSubmit={check}>
        <label>USN<input required value={usn} onChange={e=>setUsn(e.target.value.toUpperCase())} placeholder="Enter your USN" /></label>
        <button className="btn primary full" disabled={busy}>{busy?"Checking…":"Check Status"}</button>
      </form>
      {data && <div className="statusbox">
        {!data.success ? <>
          <div className="status-mark error">!</div><h3>Not found</h3><p>{data.message}</p>
        </> : <>
          <div className={`status-mark ${data.status}`}>{data.status==="approved"?"✓":data.status==="pending"?"…":"!"}</div>
          <h3>{data.status==="approved"?"Approved":data.status==="pending"?"Pending approval":"Not approved"}</h3>
          <p>{data.message}</p>
          <div className="student-summary"><b>{data.name}</b><span>{data.usn} · Year {data.year} · Section {data.section} · {data.food_preference === "non-veg" ? "Non-Veg" : "Veg"}</span></div>
          {data.status==="approved" && data.qr_token && !data.redeemed && <div className="qr-card"><QRCodeCanvas value={String(data.qr_token)} size={230}/><b>Show this QR at the food counter</b><span>Keep your screen bright while scanning.</span></div>}
          {data.redeemed && <div className="used-banner">FoodPass already redeemed.</div>}
        </>}
      </div>}
    </div>
  </div></Shell>;
}

function StaffLogin({role}) {
  const navigate=useNavigate(); const [,setStaff]=useStaff();
  const [username,setUsername]=useState(role==="scanner"?"scanner":"cloudsadmin");
  const [password,setPassword]=useState(""); const [busy,setBusy]=useState(false); const [error,setError]=useState("");
  const submit=async e=>{
    e.preventDefault();
    if(busy)return;
    setBusy(true); setError("");
    try {
      const {data,error}=await supabase.rpc("staff_login",{p_username:username.trim(),p_password:password});
      if(error) throw new Error(error.message);
      if(!data?.success) throw new Error(data?.message||"Invalid login.");
      const loggedRole=String(data.role||"").trim().toLowerCase();
      const expectedRole=role.toLowerCase();
      if(expectedRole==="admin" && loggedRole!=="admin") throw new Error("This account is not an admin account.");
      if(expectedRole==="scanner" && !["scanner","admin"].includes(loggedRole)) throw new Error("This account is not a scanner account.");
      const session={...data,role:loggedRole};
      setStaff(session);
      if(expectedRole==="scanner") sessionStorage.setItem("clouds_scanner_authenticated","1");
      navigate(expectedRole==="scanner"?"/scanner":"/admin/dashboard",{replace:true});
    } catch(err) {
      setError(err?.message||"Login failed. Please try again.");
    } finally {
      setBusy(false);
    }
  };
  return <Shell><div className="page login-page">
    <Link to="/" className="back">← FoodPass</Link>
    <div className="form-card">
      <img src="/branding/clouds.png" className="login-logo" alt="CLOUDS"/>
      <div className="eyebrow">{role==="scanner"?"SCANNER ACCESS":"ADMIN ACCESS"}</div>
      <h2>{role==="scanner"?"Scanner sign in":"Admin sign in"}</h2>
      <p className="muted">{role==="scanner"?"Sign in to open the live FoodPass scanner.":"Sign in to manage registrations."}</p>
      <form onSubmit={submit}>
        <label>Username<input value={username} onChange={e=>setUsername(e.target.value)} autoCapitalize="none" autoCorrect="off" /></label>
        <label>PIN / Password<input type="password" required value={password} onChange={e=>setPassword(e.target.value)} autoComplete="current-password" /></label>
        {error&&<div className="alert bad">{error}</div>}
        <button className="btn primary full" disabled={busy}>{busy?<><span className="button-spinner"/> Signing in…</>:"Sign In"}</button>
      </form>
    </div>
  </div></Shell>;
}

function Admin() {
  const [staff,setStaff]=useStaff(); const navigate=useNavigate();
  const [rows,setRows]=useState([]); const [loading,setLoading]=useState(true); const [working,setWorking]=useState(null);
  const [filter,setFilter]=useState("all"); const [year,setYear]=useState("all"); const [section,setSection]=useState("all"); const [search,setSearch]=useState(""); const [error,setError]=useState(""); const [showAdd,setShowAdd]=useState(false); const [showQR,setShowQR]=useState(null); const [addForm,setAddForm]=useState({type:"student",name:"",usn:"",year:"",section:"",food:""});
  const load=async()=>{
    if(!staff||staff.role!=="admin"){navigate(staff?.role==="scanner"?"/scanner":"/admin");return;}
    setLoading(true); setError("");
    const {data,error}=await supabase.rpc("admin_get_students",{p_token:staff.token});
    if(error){setError(error.message);setLoading(false);return;}
    setRows(Array.isArray(data)?data:[]);setLoading(false);
  };
  useEffect(()=>{load();},[]);
  const counts=useMemo(()=>({total:rows.length,pending:rows.filter(x=>x.status==="pending").length,approved:rows.filter(x=>x.status==="approved").length,redeemed:rows.filter(x=>x.redeemed).length,veg:rows.filter(x=>x.person_type==="student"&&x.food_preference==="veg").length,nonveg:rows.filter(x=>x.person_type==="student"&&x.food_preference==="non-veg").length}),[rows]);
  const yearSectionCounts=useMemo(()=>[1,2,3,4].map(y=>({year:y,sections:["A","B","C","D"].map(sec=>({section:sec,total:rows.filter(x=>x.person_type==="student"&&Number(x.year)===y&&x.section===sec).length,veg:rows.filter(x=>x.person_type==="student"&&Number(x.year)===y&&x.section===sec&&x.food_preference==="veg").length,nonveg:rows.filter(x=>x.person_type==="student"&&Number(x.year)===y&&x.section===sec&&x.food_preference==="non-veg").length}))})),[rows]);
  const filtered=useMemo(()=>[...rows].filter(x=>filter==="all"||x.status===filter).filter(x=>year==="all"||String(x.year)===year).filter(x=>section==="all"||x.section===section).filter(x=>`${x.full_name} ${x.usn||""}`.toLowerCase().includes(search.toLowerCase())).sort((a,b)=>({student:0,teacher:1}[a.person_type]??0)-({student:0,teacher:1}[b.person_type]??0)||Number(a.year||99)-Number(b.year||99)||(a.section||"").localeCompare(b.section||"")||a.full_name.localeCompare(b.full_name)),[rows,filter,year,section,search]);
  const approve=async id=>{setWorking(id);const {data,error}=await supabase.rpc("admin_approve_student",{p_token:staff.token,p_student_id:id});if(error||!data?.success)setError(error?.message||data?.message||"Approval failed.");else setRows(r=>r.map(x=>x.id===id?{...x,status:"approved",qr_token:data.qr_token,approved_at:new Date().toISOString()}:x));setWorking(null);};
  const reject=async id=>{setWorking(id);const {data,error}=await supabase.rpc("admin_reject_student",{p_token:staff.token,p_student_id:id});if(error||data?.success===false)setError(error?.message||data?.message||"Rejection failed.");else setRows(r=>r.map(x=>x.id===id?{...x,status:"rejected"}:x));setWorking(null);};
  const addPerson=async()=>{setWorking("add");setError("");const {data,error}=await supabase.rpc("admin_add_person",{p_token:staff.token,p_person_type:addForm.type,p_full_name:addForm.name,p_usn:addForm.type==="student"?addForm.usn:null,p_year:addForm.type==="student"?Number(addForm.year):null,p_section:addForm.type==="student"?addForm.section:null,p_food_preference:addForm.type==="student"?addForm.food:null,p_status:"pending"});if(error||!data?.success)setError(error?.message||data?.message||"Could not add user.");else{setShowAdd(false);setAddForm({type:"student",name:"",usn:"",year:"",section:"",food:""});await load();}setWorking(null);};
  const remove=async student=>{
    if(!window.confirm(`Delete ${student.full_name} (${student.usn}) permanently?`))return;
    setWorking(`delete-${student.id}`);const {data,error}=await supabase.rpc("admin_delete_student",{p_token:staff.token,p_student_id:student.id});
    if(error||!data?.success)setError(error?.message||data?.message||"Delete failed.");else setRows(r=>r.filter(x=>x.id!==student.id));setWorking(null);
  };
  const logout=async()=>{await supabase.rpc("staff_logout",{p_token:staff.token});setStaff(null);navigate("/")};
  return <Shell><div className="dashboard">
    <div className="dashhead"><div><div className="eyebrow">CLOUDS / ADMIN</div><h2>FoodPass Control</h2><p className="muted">Approvals, registrations and event users.</p></div><div className="dash-actions"><button className="btn primary small" onClick={()=>setShowAdd(true)}>+ Add User</button><button className="btn outline small" onClick={logout}>Logout</button></div></div>
    <div className="stats"><div><span>Total</span><b>{counts.total}</b></div><div><span>Pending</span><b>{counts.pending}</b></div><div><span>Approved</span><b>{counts.approved}</b></div><div><span>Redeemed</span><b>{counts.redeemed}</b></div></div>
    <div className="food-summary"><div><b>{counts.veg}</b><span>Veg</span></div><div><b>{counts.nonveg}</b><span>Non-Veg</span></div></div><div className="year-food-summary">{yearSectionCounts.map(group=><div className="year-food-group" key={group.year}><div className="year-food-title">Year {group.year}</div><div className="year-food-grid">{group.sections.map(x=><div className="year-food-cell" key={x.section}><b>{x.total}</b><span>Section {x.section}</span><small>V {x.veg} · NV {x.nonveg}</small></div>)}</div></div>)}</div><div className="filters"><input placeholder="Search name or USN" value={search} onChange={e=>setSearch(e.target.value)}/><select value={year} onChange={e=>setYear(e.target.value)}><option value="all">All years</option><option value="1">1st Year</option><option value="2">2nd Year</option><option value="3">3rd Year</option><option value="4">4th Year</option></select><select value={section} onChange={e=>setSection(e.target.value)}><option value="all">All sections</option><option value="A">Section A</option><option value="B">Section B</option><option value="C">Section C</option><option value="D">Section D</option></select><select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All status</option><option value="pending">Pending</option><option value="approved">Approved</option><option value="rejected">Rejected</option></select></div>
    {error&&<div className="alert bad dashboard-alert">{error}</div>}
    <div className="table-card">{loading&&<Loading text="Loading registrations…"/>}
      {!loading&&filtered.map(student=><div className="student" key={student.id}>
        <div className="student-main"><div className="avatar">{student.full_name?.slice(0,1)?.toUpperCase()}</div><div><b>{student.full_name}</b><span>{student.person_type==="teacher"?"Teacher":"Student"}{student.usn?` · ${student.usn}`:""}{student.year?` · Year ${student.year}`:""}{student.section?` · Section ${student.section}`:""}{student.person_type==="student"&&student.food_preference?` · ${student.food_preference==="non-veg"?"Non-Veg":"Veg"}`:""}</span></div></div>
        <span className={`pill ${student.status}`}>{student.status}</span>{student.redeemed&&<span className="pill used">used</span>}
        <div className="rowactions">{student.status==="pending"&&<><button className="mini approve" disabled={working===student.id} onClick={()=>approve(student.id)}>{working===student.id?"…":"Approve"}</button><button className="mini reject" disabled={working===student.id} onClick={()=>reject(student.id)}>Reject</button></>}{student.status==="approved"&&student.qr_token&&<button className="mini" onClick={()=>setShowQR(student)}>QR</button>}<button className="mini delete" disabled={working===`delete-${student.id}`} onClick={()=>remove(student)}>{working===`delete-${student.id}`?"…":"Delete"}</button></div>
      </div>)}
      {!loading&&!filtered.length&&<div className="empty">No students match the current filters.</div>}
    </div>
    {showAdd&&<div className="modal-backdrop"><div className="modal"><div className="modal-head"><div><div className="eyebrow">ADMIN / ADD USER</div><h3>Add event user</h3></div><button className="close" onClick={()=>setShowAdd(false)}>×</button></div><div className="type-tabs"><button className={addForm.type==="student"?"active":""} onClick={()=>setAddForm({...addForm,type:"student"})}>Student</button><button className={addForm.type==="teacher"?"active":""} onClick={()=>setAddForm({...addForm,type:"teacher"})}>Teacher</button></div><label>Full name<input value={addForm.name} onChange={e=>setAddForm({...addForm,name:e.target.value})}/></label>{addForm.type==="student"?<div className="two-fields"><label>USN<input value={addForm.usn} onChange={e=>setAddForm({...addForm,usn:e.target.value.toUpperCase()})}/></label><label>Year<select value={addForm.year} onChange={e=>setAddForm({...addForm,year:e.target.value})}><option value="">Year</option><option value="1">1st</option><option value="2">2nd</option><option value="3">3rd</option><option value="4">4th</option></select></label><label>Section<select value={addForm.section} onChange={e=>setAddForm({...addForm,section:e.target.value})}><option value="">Section</option><option value="A">A</option><option value="B">B</option><option value="C">C</option><option value="D">D</option></select></label><label>Food<select value={addForm.food} onChange={e=>setAddForm({...addForm,food:e.target.value})}><option value="">Food</option><option value="veg">Veg</option><option value="non-veg">Non-Veg</option></select></label></div>:<p className="muted">Teachers don't need a USN, year or section. They can be approved and issued a FoodPass QR.</p>}<button className="btn primary full" disabled={working==="add"} onClick={addPerson}>{working==="add"?"Adding…":"Add User"}</button></div></div>}
    {showQR&&<div className="modal-backdrop"><div className="modal qr-modal"><div className="modal-head"><div><div className="eyebrow">FOODPASS QR</div><h3>{showQR.full_name}</h3></div><button className="close" onClick={()=>setShowQR(null)}>×</button></div><div className="admin-qr"><QRCodeCanvas value={String(showQR.qr_token)} size={260}/><b>{showQR.person_type==="teacher"?"Teacher":"Student"}</b><span>{showQR.usn||showQR.foodpass_code||"FoodPass"}</span><small>{showQR.person_type==="student"&&showQR.food_preference?showQR.food_preference==="non-veg"?"Non-Veg":"Veg":"Event FoodPass"}</small></div></div></div>}
  </div></Shell>;
}

function ScannerPage() {
  const [staff,setStaff]=useStaff(); const navigate=useNavigate();
  const [result,setResult]=useState(null); const [logs,setLogs]=useState([]); const [logsLoading,setLogsLoading]=useState(true); const [logsError,setLogsError]=useState(""); const scannerRef=useRef(null);
  const loadLogs=async()=>{
    if(!staff?.token)return;
    const {data,error}=await supabase.rpc("scanner_get_logs",{p_token:staff.token,p_limit:40});
    if(error)setLogsError(error.message); else setLogs(Array.isArray(data)?data:[]);
    setLogsLoading(false);
  };
  useEffect(()=>{
    const currentRole=String(staff?.role||"").trim().toLowerCase();
    if(!staff||!["scanner","admin"].includes(currentRole)){navigate("/scanner");return;}
    loadLogs();
    let locked=false;
    const scanner=new Html5QrcodeScanner("reader",{fps:10,qrbox:{width:260,height:260},rememberLastUsedCamera:true,showTorchButtonIfSupported:true},false);
    scannerRef.current=scanner;
    scanner.render(async decoded=>{
      if(locked)return; locked=true;
      const {data,error}=await supabase.rpc("redeem_qr",{p_token:staff.token,p_qr_token:decoded});
      const r=error?{result:"INVALID",message:error.message}:data;
      setResult(r);
      await loadLogs();
      setTimeout(()=>{setResult(null);locked=false;},5500);
    },()=>{});
    return()=>{try{scanner.clear()}catch{}};
  },[]);
  const logout=async()=>{await supabase.rpc("staff_logout",{p_token:staff.token});setStaff(null);navigate("/")};
  const resultTitle=result?.result==="VALID"?"VALID FOODPASS":result?.result==="ALREADY_USED"?"ALREADY USED":result?.result==="NOT_APPROVED"?"NOT APPROVED":result?.result==="UNAUTHORIZED"?"SESSION EXPIRED":"INVALID QR";
  return <Shell><div className="scannerpage">
    <div className="dashhead"><div><div className="eyebrow">CLOUDS / EVENT DAY</div><h2>FoodPass Scanner</h2><p className="muted">Scan, verify, serve. One approved QR can be redeemed once.</p></div><button className="btn outline small" onClick={logout}>Logout</button></div>
    <div className="scanner-grid">
      <div className="scanner-card"><div className="scanner-label">LIVE CAMERA</div><div id="reader"/><div className="scan-hint">Place the QR inside the frame</div></div>
      <div className="log-card">
        <div className="log-head"><div><b>Scan log</b><span>Latest event activity</span></div><button className="refresh" onClick={loadLogs}>Refresh</button></div>
        {logsLoading?<div className="log-empty">Loading logs…</div>:logsError?<div className="log-empty error-text">{logsError}</div>:logs.length===0?<div className="log-empty">No scans yet.</div>:
          <div className="logs">{logs.map((log,i)=><div className="log-row" key={`${log.scanned_at}-${i}`}><div className={`log-dot ${String(log.result).toLowerCase()}`}/><div className="log-main"><b>{log.usn||"Unknown QR"}</b><span>{log.full_name||"Unregistered / invalid"}{log.section ? ` · Section ${log.section}` : ""}{log.food_preference ? ` · ${log.food_preference === "non-veg" ? "Non-Veg" : "Veg"}` : ""} · {log.result}</span></div><time>{formatTime(log.scanned_at)}</time></div>)}</div>}
      </div>
    </div>
    {result&&<div className={`scan-result ${result.result==="VALID"?"success":"failure"}`}>
      <div className="scan-result-top"><span>{result.result==="VALID"?"✓":"!"}</span><div><small>SCAN RESULT</small><h3>{resultTitle}</h3></div></div>
      {result.name&&<div className="verified-person"><b>{result.name}</b><span>{result.usn || "Teacher"} · {result.year ? `Year ${result.year}` : "Staff"}{result.section ? ` · Section ${result.section}` : ""} · {result.food_preference === "non-veg" ? "Non-Veg" : result.food_preference === "veg" ? "Veg" : "No preference"}</span></div>}
      <p>{result.message}</p>
      <div className="scan-result-note">{result.result==="VALID"?"Food may be served.":result.result==="ALREADY_USED"?"Do not serve again.":"Do not redeem this QR."}</div>
    </div>}
  </div></Shell>;
}

function formatTime(value){
  if(!value)return "—";
  const d=new Date(value);
  return d.toLocaleTimeString([], {hour:"2-digit",minute:"2-digit",second:"2-digit"});
}

function ScannerRoute(){
  const [staff]=useStaff();
  const role=String(staff?.role||"").trim().toLowerCase();
  const [authenticated,setAuthenticated]=useState(()=>sessionStorage.getItem("clouds_scanner_authenticated")==="1");
  useEffect(()=>{
    if(!authenticated || !staff || !["scanner","admin"].includes(role)) return;
  },[authenticated,staff,role]);
  if(!authenticated || !staff || !["scanner","admin"].includes(role)) return <StaffLogin role="scanner"/>;
  return <ScannerPage/>;
}

export default function App(){
  return <Routes>
    <Route path="/" element={<Home/>}/>
    <Route path="/register" element={<Register/>}/>
    <Route path="/status" element={<Status/>}/>
    <Route path="/admin" element={<StaffLogin role="admin"/>}/>
    <Route path="/admin/dashboard" element={<Admin/>}/>
    <Route path="/scanner" element={<ScannerRoute/>}/>
    <Route path="*" element={<Home/>}/>
  </Routes>;
}