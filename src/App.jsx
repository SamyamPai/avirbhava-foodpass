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
    try {
      return JSON.parse(localStorage.getItem("clouds_staff") || "null");
    } catch {
      return null;
    }
  });

  const setStaff = (value) => {
    if (value) {
      localStorage.setItem("clouds_staff", JSON.stringify(value));
    } else {
      localStorage.removeItem("clouds_staff");
    }

    setStaffState(value);
  };

  return [staff, setStaff];
}

function Shell({ children }) {
  return (
    <div className="app">
      <header className="topbar">
        <Link to="/" className="header-brand">
          <img
            src="/branding/sahyadri.png"
            alt="Sahyadri College"
            className="header-sahyadri"
          />

          <div className="header-divider" />

          <img
            src="/branding/clouds.png"
            alt="CLOUDS"
            className="header-clouds"
          />

          <div className="header-copy">
            <strong>CLOUDS</strong>
            <span>Avirbhava'26 · FoodPass</span>
          </div>
        </Link>
      </header>

      <main>{children}</main>

      <footer>
        <div className="footer-line">
          <span>
            {BRAND.college} · {BRAND.location}
          </span>
          <span>{BRAND.association}</span>
        </div>

        <div className="footer-credit">
          made by <b>SAMYAM PAI</b>
        </div>
      </footer>
    </div>
  );
}

function Loading({ text = "Please wait…" }) {
  return (
    <div className="loading">
      <div className="spinner" />
      <span>{text}</span>
    </div>
  );
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

            <h1>
              Avirbhava'26
              <br />
              <span></span>
            </h1>

            <p>
              Your digital food pass for the event. Register with your USN,
              check your approval, and show your QR code when food is served.
            </p>

            <div className="hero-actions">
              <Link to="/register" className="btn primary">
                Register <span>→</span>
              </Link>

              <Link to="/status" className="btn outline">
                Check Status
              </Link>
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
              <span>REGISTER</span>
              <i>—</i>
              <span>APPROVE</span>
              <i>—</i>
              <span>SCAN</span>
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
  const [form, setForm] = useState({
    name: "",
    usn: "",
    year: "",
    section: "",
    food: "",
  });

  const USN_RE = /^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$/i;

  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  const submit = async (e) => {
    e.preventDefault();

    const cleanUSN = form.usn.trim().toUpperCase();

    if (!USN_RE.test(cleanUSN)) {
      setMsg({
        bad: true,
        text: "Invalid USN. Please enter a valid CS USN such as 4SF24CS181.",
      });
      return;
    }

    setBusy(true);
    setMsg(null);

    const { data, error } = await supabase.rpc("register_student", {
      p_full_name: form.name.trim(),
      p_section: form.section,
      p_year: Number(form.year),
      p_usn: cleanUSN,
      p_food_preference: form.food,
    });

    setBusy(false);

    if (error) {
      setMsg({
        bad: true,
        text: error.message,
      });
    } else if (!data?.success) {
      setMsg({
        bad: true,
        text: data?.message || "Registration failed.",
      });
    } else {
      setMsg({
        bad: false,
        text: "Registration successful. Check your status later using your USN.",
      });

      setForm({
        name: "",
        usn: "",
        year: "",
        section: "",
        food: "",
      });
    }
  };

  return (
    <Shell>
      <div className="page">
        <Link to="/" className="back">
          ← FoodPass
        </Link>

        <div className="form-card">
          <div className="eyebrow">01 / REGISTER</div>

          <h2>Get your FoodPass</h2>

          <p className="muted">
            Use the same name and USN used by the college.
          </p>

          <form onSubmit={submit}>
            <label>
              Full name
              <input
                required
                value={form.name}
                onChange={(e) =>
                  setForm({
                    ...form,
                    name: e.target.value,
                  })
                }
                placeholder="Your full name"
              />
            </label>

            <label>
              USN
              <input
                required
                value={form.usn}
                onChange={(e) =>
                  setForm({
                    ...form,
                    usn: e.target.value.toUpperCase(),
                  })
                }
                placeholder="4SF24CS001"
                maxLength={9}
              />
            </label>

            <div className="two-fields">
              <label>
                Year
                <select
                  required
                  value={form.year}
                  onChange={(e) =>
                    setForm({
                      ...form,
                      year: e.target.value,
                    })
                  }
                >
                  <option value="">Select year</option>
                  <option value="1">1st Year</option>
                  <option value="2">2nd Year</option>
                  <option value="3">3rd Year</option>
                  <option value="4">4th Year</option>
                </select>
              </label>

              <label>
                Section
                <select
                  required
                  value={form.section}
                  onChange={(e) =>
                    setForm({
                      ...form,
                      section: e.target.value,
                    })
                  }
                >
                  <option value="">Select section</option>
                  <option value="A">A</option>
                  <option value="B">B</option>
                  <option value="C">C</option>
                  <option value="D">D</option>
                </select>
              </label>

              <label>
                Food Preference
                <select
                  required
                  value={form.food}
                  onChange={(e) =>
                    setForm({
                      ...form,
                      food: e.target.value,
                    })
                  }
                >
                  <option value="">Select preference</option>
                  <option value="veg">Veg</option>
                  <option value="non-veg">Non-Veg</option>
                </select>
              </label>
            </div>

            {msg && (
              <div className={`alert ${msg.bad ? "bad" : "good"}`}>
                {msg.text}
              </div>
            )}

            <button className="btn primary full" disabled={busy}>
              {busy ? "Submitting…" : "Submit Registration"}
            </button>
          </form>

          <div className="form-foot">
            Already registered?{" "}
            <Link to="/status">Check your status →</Link>
          </div>
        </div>
      </div>
    </Shell>
  );
}

function Status() {
  const [usn, setUsn] = useState("");
  const [busy, setBusy] = useState(false);
  const [data, setData] = useState(null);

  const check = async (e) => {
    e.preventDefault();

    setBusy(true);
    setData(null);

    const { data, error } = await supabase.rpc("get_student_status", {
      p_usn: usn.trim().toUpperCase(),
    });

    setBusy(false);

    setData(
      error
        ? {
            success: false,
            message: error.message,
          }
        : data
    );
  };

  return (
    <Shell>
      <div className="page">
        <Link to="/" className="back">
          ← FoodPass
        </Link>

        <div className="form-card">
          <div className="eyebrow">02 / STATUS</div>

          <h2>Check your FoodPass</h2>

          <p className="muted">Enter your USN. That's all.</p>

          <form onSubmit={check}>
            <label>
              USN
              <input
                required
                value={usn}
                onChange={(e) =>
                  setUsn(e.target.value.toUpperCase())
                }
                placeholder="Enter your USN"
                maxLength={9}
              />
            </label>

            <button className="btn primary full" disabled={busy}>
              {busy ? "Checking…" : "Check Status"}
            </button>
          </form>

          {data && (
            <div className="statusbox">
              {!data.success ? (
                <>
                  <div className="status-mark error">!</div>
                  <h3>Not found</h3>
                  <p>{data.message}</p>
                </>
              ) : (
                <>
                  <div className={`status-mark ${data.status}`}>
                    {data.status === "approved"
                      ? "✓"
                      : data.status === "pending"
                      ? "…"
                      : "!"}
                  </div>

                  <h3>
                    {data.status === "approved"
                      ? "Approved"
                      : data.status === "pending"
                      ? "Pending approval"
                      : "Not approved"}
                  </h3>

                  <p>{data.message}</p>

                  <div className="student-summary">
                    <b>{data.name}</b>

                    <span>
                      {data.usn} · Year {data.year} · Section{" "}
                      {data.section} ·{" "}
                      {data.food_preference === "non-veg"
                        ? "Non-Veg"
                        : "Veg"}
                    </span>
                  </div>

                  {data.status === "approved" &&
                    data.qr_token &&
                    !data.redeemed && (
                      <div className="qr-card">
                        <QRCodeCanvas
                          value={String(data.qr_token)}
                          size={280}
                          level="M"
                          marginSize={2}
                          style={{
                            width: "100%",
                            maxWidth: "280px",
                            height: "auto",
                            display: "block",
                          }}
                        />

                        <b>Show this QR at the food counter</b>

                        <span>
                          Keep your screen bright while scanning.
                        </span>
                      </div>
                    )}

                  {data.redeemed && (
                    <div className="used-banner">
                      FoodPass already redeemed.
                    </div>
                  )}
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </Shell>
  );
}

function StaffLogin({ role }) {
  const navigate = useNavigate();
  const [, setStaff] = useStaff();

  const [username, setUsername] = useState(
    role === "scanner" ? "scanner" : "cloudsadmin"
  );

  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const submit = async (e) => {
    e.preventDefault();

    if (busy) return;

    setBusy(true);
    setError("");

    try {
      const { data, error } = await supabase.rpc("staff_login", {
        p_username: username.trim(),
        p_password: password,
      });

      if (error) {
        throw new Error(error.message);
      }

      if (!data?.success) {
        throw new Error(data?.message || "Invalid login.");
      }

      const loggedRole = String(data.role || "")
        .trim()
        .toLowerCase();

      const expectedRole = role.toLowerCase();

      if (
        expectedRole === "admin" &&
        loggedRole !== "admin"
      ) {
        throw new Error(
          "This account is not an admin account."
        );
      }

      if (
        expectedRole === "scanner" &&
        !["scanner", "admin"].includes(loggedRole)
      ) {
        throw new Error(
          "This account is not a scanner account."
        );
      }

      const session = {
        ...data,
        role: loggedRole,
      };

      setStaff(session);

      if (expectedRole === "scanner") {
        sessionStorage.setItem(
          "clouds_scanner_authenticated",
          "1"
        );
      }

      navigate(
        expectedRole === "scanner"
          ? "/scanner"
          : "/admin/dashboard",
        { replace: true }
      );
    } catch (err) {
      setError(
        err?.message ||
          "Login failed. Please try again."
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <Shell>
      <div className="page">
        <Link to="/" className="back">
          ← FoodPass
        </Link>

        <div className="form-card">
          <img
            src="/branding/clouds.png"
            alt="CLOUDS"
            className="login-logo"
          />

          <div className="eyebrow">
            {role === "admin"
              ? "ADMIN PORTAL"
              : "SCANNER PORTAL"}
          </div>

          <h2>
            {role === "admin"
              ? "Admin Login"
              : "Scanner Login"}
          </h2>

          <p className="muted">
            Enter your staff credentials to continue.
          </p>

          <form onSubmit={submit}>
            <label>
              Username
              <input
                required
                value={username}
                onChange={(e) =>
                  setUsername(e.target.value)
                }
              />
            </label>

            <label>
              PIN / Password
              <input
                required
                type="password"
                value={password}
                onChange={(e) =>
                  setPassword(e.target.value)
                }
              />
            </label>

            {error && (
              <div className="alert bad">
                {error}
              </div>
            )}

            <button
              className="btn primary full"
              disabled={busy}
            >
              {busy ? "Logging in…" : "Login"}
            </button>
          </form>
        </div>
      </div>
    </Shell>
  );
}

/*
  Keep the rest of your existing Admin and Scanner components
  exactly as they currently are.

  The only QR-related change required for this fix is the
  responsive QR implementation in Status above.
*/

function Admin() {
  const [staff, setStaff] = useStaff();

  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState(null);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [filterYear, setFilterYear] = useState("");
  const [filterSection, setFilterSection] = useState("");
  const [showAdd, setShowAdd] = useState(false);
  const [showQR, setShowQR] = useState(null);

  const [addForm, setAddForm] = useState({
    type: "student",
    name: "",
    usn: "",
    year: "",
    section: "",
    food: "",
  });

  const loadStudents = async () => {
    if (!staff?.token) return;

    setLoading(true);
    setError("");

    const { data, error } = await supabase.rpc(
      "admin_get_students",
      {
        p_token: staff.token,
      }
    );

    if (error) {
      setError(error.message);
    } else {
      setStudents(data || []);
    }

    setLoading(false);
  };

  useEffect(() => {
    loadStudents();
  }, [staff]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();

    return students.filter((student) => {
      const matchesSearch =
        !q ||
        student.full_name?.toLowerCase().includes(q) ||
        student.usn?.toLowerCase().includes(q);

      const matchesYear =
        !filterYear ||
        String(student.year) === String(filterYear);

      const matchesSection =
        !filterSection ||
        student.section === filterSection;

      return (
        matchesSearch &&
        matchesYear &&
        matchesSection
      );
    });
  }, [
    students,
    search,
    filterYear,
    filterSection,
  ]);

  const approve = async (id) => {
    setWorking(id);
    setError("");

    const { data, error } = await supabase.rpc(
      "admin_approve_student",
      {
        p_token: staff.token,
        p_student_id: id,
      }
    );

    if (error) {
      setError(error.message);
    } else if (!data?.success) {
      setError(data?.message || "Approval failed.");
    } else {
      await loadStudents();
    }

    setWorking(null);
  };

  const reject = async (id) => {
    setWorking(id);
    setError("");

    const { data, error } = await supabase.rpc(
      "admin_reject_student",
      {
        p_token: staff.token,
        p_student_id: id,
      }
    );

    if (error) {
      setError(error.message);
    } else if (!data?.success) {
      setError(data?.message || "Rejection failed.");
    } else {
      await loadStudents();
    }

    setWorking(null);
  };

  const remove = async (student) => {
    if (
      !window.confirm(
        `Delete ${student.full_name}?`
      )
    ) {
      return;
    }

    setWorking(`delete-${student.id}`);
    setError("");

    const { data, error } = await supabase.rpc(
      "admin_delete_student",
      {
        p_token: staff.token,
        p_student_id: student.id,
      }
    );

    if (error) {
      setError(error.message);
    } else if (!data?.success) {
      setError(data?.message || "Delete failed.");
    } else {
      await loadStudents();
    }

    setWorking(null);
  };

  const addPerson = async () => {
    if (!addForm.name.trim()) {
      setError("Name is required.");
      return;
    }

    setWorking("add");
    setError("");

    const { data, error } = await supabase.rpc(
      "admin_add_user",
      {
        p_token: staff.token,
        p_full_name: addForm.name.trim(),
        p_person_type: addForm.type,
        p_usn:
          addForm.type === "student"
            ? addForm.usn.trim().toUpperCase()
            : null,
        p_year:
          addForm.type === "student"
            ? Number(addForm.year)
            : null,
        p_section:
          addForm.type === "student"
            ? addForm.section
            : null,
        p_food_preference:
          addForm.type === "student"
            ? addForm.food
            : null,
      }
    );

    if (error) {
      setError(error.message);
    } else if (!data?.success) {
      setError(
        data?.message || "Could not add user."
      );
    } else {
      setShowAdd(false);

      setAddForm({
        type: "student",
        name: "",
        usn: "",
        year: "",
        section: "",
        food: "",
      });

      await loadStudents();
    }

    setWorking(null);
  };

  const logout = () => {
    setStaff(null);
    sessionStorage.removeItem(
      "clouds_scanner_authenticated"
    );
  };

  const total = students.length;
  const pending = students.filter(
    (s) => s.status === "pending"
  ).length;
  const approved = students.filter(
    (s) => s.status === "approved"
  ).length;
  const redeemed = students.filter(
    (s) => s.redeemed
  ).length;

  return (
    <Shell>
      <div className="dashboard">
        <div className="dashhead">
          <div>
            <div className="eyebrow">
              CLOUDS / ADMIN
            </div>

            <h2>FoodPass registrations</h2>

            <p className="muted">
              Manage registrations, approvals and
              QR passes.
            </p>
          </div>

          <div className="hero-actions">
            <button
              className="btn outline"
              onClick={() => setShowAdd(true)}
            >
              + Add User
            </button>

            <button
              className="btn outline"
              onClick={logout}
            >
              Logout
            </button>
          </div>
        </div>

        {error && (
          <div className="alert bad dashboard-alert">
            {error}
          </div>
        )}

        <div className="stats">
          <div>
            <span>Total</span>
            <b>{total}</b>
          </div>

          <div>
            <span>Pending</span>
            <b>{pending}</b>
          </div>

          <div>
            <span>Approved</span>
            <b>{approved}</b>
          </div>

          <div>
            <span>Redeemed</span>
            <b>{redeemed}</b>
          </div>
        </div>

        <div className="filters">
          <input
            value={search}
            onChange={(e) =>
              setSearch(e.target.value)
            }
            placeholder="Search name or USN..."
          />

          <select
            value={filterYear}
            onChange={(e) =>
              setFilterYear(e.target.value)
            }
          >
            <option value="">All Years</option>
            <option value="1">1st Year</option>
            <option value="2">2nd Year</option>
            <option value="3">3rd Year</option>
            <option value="4">4th Year</option>
          </select>

          <select
            value={filterSection}
            onChange={(e) =>
              setFilterSection(e.target.value)
            }
          >
            <option value="">All Sections</option>
            <option value="A">Section A</option>
            <option value="B">Section B</option>
            <option value="C">Section C</option>
            <option value="D">Section D</option>
          </select>
        </div>

        <div className="table-card">
          {loading && <Loading text="Loading registrations…" />}

          {!loading &&
            filtered.map((student) => (
              <div
                className="student"
                key={student.id}
              >
                <div className="student-main">
                  <div className="avatar">
                    {student.full_name
                      ?.slice(0, 1)
                      ?.toUpperCase()}
                  </div>

                  <div>
                    <b>{student.full_name}</b>

                    <span>
                      {student.person_type ===
                      "teacher"
                        ? "Teacher"
                        : "Student"}

                      {student.usn
                        ? ` · ${student.usn}`
                        : ""}

                      {student.year
                        ? ` · Year ${student.year}`
                        : ""}

                      {student.section
                        ? ` · Section ${student.section}`
                        : ""}

                      {student.person_type ===
                        "student" &&
                      student.food_preference
                        ? ` · ${
                            student.food_preference ===
                            "non-veg"
                              ? "Non-Veg"
                              : "Veg"
                          }`
                        : ""}
                    </span>
                  </div>
                </div>

                <span
                  className={`pill ${student.status}`}
                >
                  {student.status}
                </span>

                {student.redeemed && (
                  <span className="pill used">
                    used
                  </span>
                )}

                <div className="rowactions">
                  {student.status ===
                    "pending" && (
                    <>
                      <button
                        className="mini approve"
                        disabled={
                          working === student.id
                        }
                        onClick={() =>
                          approve(student.id)
                        }
                      >
                        {working === student.id
                          ? "…"
                          : "Approve"}
                      </button>

                      <button
                        className="mini reject"
                        disabled={
                          working === student.id
                        }
                        onClick={() =>
                          reject(student.id)
                        }
                      >
                        Reject
                      </button>
                    </>
                  )}

                  {student.status ===
                    "approved" &&
                    student.qr_token && (
                      <button
                        className="mini"
                        onClick={() =>
                          setShowQR(student)
                        }
                      >
                        QR
                      </button>
                    )}

                  <button
                    className="mini delete"
                    disabled={
                      working ===
                      `delete-${student.id}`
                    }
                    onClick={() =>
                      remove(student)
                    }
                  >
                    {working ===
                    `delete-${student.id}`
                      ? "…"
                      : "Delete"}
                  </button>
                </div>
              </div>
            ))}

          {!loading &&
            !filtered.length && (
              <div className="empty">
                No students match the current
                filters.
              </div>
            )}
        </div>

        {showAdd && (
          <div className="modal-backdrop">
            <div className="modal">
              <div className="modal-head">
                <div>
                  <div className="eyebrow">
                    ADMIN / ADD USER
                  </div>

                  <h3>Add event user</h3>
                </div>

                <button
                  className="close"
                  onClick={() =>
                    setShowAdd(false)
                  }
                >
                  ×
                </button>
              </div>

              <div className="type-tabs">
                <button
                  className={
                    addForm.type === "student"
                      ? "active"
                      : ""
                  }
                  onClick={() =>
                    setAddForm({
                      ...addForm,
                      type: "student",
                    })
                  }
                >
                  Student
                </button>

                <button
                  className={
                    addForm.type === "teacher"
                      ? "active"
                      : ""
                  }
                  onClick={() =>
                    setAddForm({
                      ...addForm,
                      type: "teacher",
                    })
                  }
                >
                  Teacher
                </button>
              </div>

              <label>
                Full name
                <input
                  value={addForm.name}
                  onChange={(e) =>
                    setAddForm({
                      ...addForm,
                      name: e.target.value,
                    })
                  }
                />
              </label>

              {addForm.type === "student" ? (
                <div className="two-fields">
                  <label>
                    USN
                    <input
                      value={addForm.usn}
                      onChange={(e) =>
                        setAddForm({
                          ...addForm,
                          usn: e.target.value.toUpperCase(),
                        })
                      }
                      maxLength={9}
                    />
                  </label>

                  <label>
                    Year
                    <select
                      value={addForm.year}
                      onChange={(e) =>
                        setAddForm({
                          ...addForm,
                          year: e.target.value,
                        })
                      }
                    >
                      <option value="">
                        Year
                      </option>
                      <option value="1">
                        1st
                      </option>
                      <option value="2">
                        2nd
                      </option>
                      <option value="3">
                        3rd
                      </option>
                      <option value="4">
                        4th
                      </option>
                    </select>
                  </label>

                  <label>
                    Section
                    <select
                      value={addForm.section}
                      onChange={(e) =>
                        setAddForm({
                          ...addForm,
                          section: e.target.value,
                        })
                      }
                    >
                      <option value="">
                        Section
                      </option>
                      <option value="A">
                        A
                      </option>
                      <option value="B">
                        B
                      </option>
                      <option value="C">
                        C
                      </option>
                      <option value="D">
                        D
                      </option>
                    </select>
                  </label>

                  <label>
                    Food
                    <select
                      value={addForm.food}
                      onChange={(e) =>
                        setAddForm({
                          ...addForm,
                          food: e.target.value,
                        })
                      }
                    >
                      <option value="">
                        Food
                      </option>
                      <option value="veg">
                        Veg
                      </option>
                      <option value="non-veg">
                        Non-Veg
                      </option>
                    </select>
                  </label>
                </div>
              ) : (
                <p className="muted">
                  Teachers don't need a USN, year or
                  section. They can be approved and
                  issued a FoodPass QR.
                </p>
              )}

              <button
                className="btn primary full"
                disabled={working === "add"}
                onClick={addPerson}
              >
                {working === "add"
                  ? "Adding…"
                  : "Add User"}
              </button>
            </div>
          </div>
        )}

        {showQR && (
          <div className="modal-backdrop">
            <div className="modal qr-modal">
              <div className="modal-head">
                <div>
                  <div className="eyebrow">
                    FOODPASS QR
                  </div>

                  <h3>{showQR.full_name}</h3>
                </div>

                <button
                  className="close"
                  onClick={() =>
                    setShowQR(null)
                  }
                >
                  ×
                </button>
              </div>

              <div className="admin-qr">
                <QRCodeCanvas
                  value={String(showQR.qr_token)}
                  size={280}
                  level="M"
                  marginSize={2}
                  style={{
                    width: "100%",
                    maxWidth: "280px",
                    height: "auto",
                    display: "block",
                  }}
                />

                <b>
                  {showQR.person_type === "teacher"
                    ? "Teacher"
                    : "Student"}
                </b>

                <span>
                  {showQR.usn ||
                    showQR.foodpass_code ||
                    "FoodPass"}
                </span>

                <small>
                  {showQR.person_type ===
                    "student" &&
                  showQR.food_preference
                    ? showQR.food_preference ===
                      "non-veg"
                      ? "Non-Veg"
                      : "Veg"
                    : "Event FoodPass"}
                </small>
              </div>
            </div>
          </div>
        )}
      </div>
    </Shell>
  );
}

function ScannerPage() {
  const [staff] = useStaff();
  const navigate = useNavigate();

  const [result, setResult] = useState(null);
  const [logs, setLogs] = useState([]);
  const [logsLoading, setLogsLoading] =
    useState(true);
  const [logsError, setLogsError] = useState("");

  const scannerRef = useRef(null);

  const loadLogs = async () => {
    if (!staff?.token) return;

    setLogsLoading(true);
    setLogsError("");

    const { data, error } = await supabase.rpc(
      "scanner_get_logs",
      {
        p_token: staff.token,
      }
    );

    if (error) {
      setLogsError(error.message);
    } else {
      setLogs(data || []);
    }

    setLogsLoading(false);
  };

  useEffect(() => {
    if (!staff?.token) {
      navigate("/scanner", {
        replace: true,
      });
      return;
    }

    loadLogs();

    const scanner = new Html5QrcodeScanner(
      "reader",
      {
        fps: 8,
        qrbox: {
          width: 250,
          height: 250,
        },
        rememberLastUsedCamera: true,
        showTorchButtonIfSupported: true,
      },
      false
    );

    scannerRef.current = scanner;

    const onScanSuccess = async (decodedText) => {
      try {
        await scanner.clear();
      } catch {}

      const { data, error } = await supabase.rpc(
        "scanner_redeem_qr",
        {
          p_token: staff.token,
          p_qr_token: decodedText,
        }
      );

      if (error) {
        setResult({
          success: false,
          title: "Scan failed",
          message: error.message,
        });
      } else {
        setResult(data);
      }

      await loadLogs();

      setTimeout(() => {
        if (scannerRef.current) {
          try {
            scannerRef.current.render(
              onScanSuccess,
              () => {}
            );
          } catch {}
        }
      }, 1500);
    };

    scanner.render(onScanSuccess, () => {});

    return () => {
      try {
        scanner.clear();
      } catch {}
    };
  }, [staff, navigate]);

  const logout = () => {
    try {
      scannerRef.current?.clear();
    } catch {}

    sessionStorage.removeItem(
      "clouds_scanner_authenticated"
    );

    navigate("/scanner", {
      replace: true,
    });
  };

  return (
    <Shell>
      <div className="scannerpage">
        <div className="dashhead">
          <div>
            <div className="eyebrow">
              CLOUDS / SCANNER
            </div>

            <h2>FoodPass Scanner</h2>

            <p className="muted">
              Scan the student's QR code to verify
              and redeem their FoodPass.
            </p>
          </div>

          <button
            className="btn outline"
            onClick={logout}
          >
            Logout
          </button>
        </div>

        <div className="scanner-grid">
          <div className="scanner-card">
            <div className="scanner-label">
              SCAN FOODPASS QR
            </div>

            <div id="reader" />

            <div className="scan-hint">
              Keep the QR code inside the frame.
            </div>
          </div>

          <div className="log-card">
            <div className="log-head">
              <div>
                <b>Scan Logs</b>
                <span>
                  Recent FoodPass verification
                </span>
              </div>

              <button
                className="refresh"
                onClick={loadLogs}
              >
                Refresh
              </button>
            </div>

            <div className="logs">
              {logsLoading && (
                <div className="log-empty">
                  Loading logs…
                </div>
              )}

              {logsError && (
                <div className="log-empty error-text">
                  {logsError}
                </div>
              )}

              {!logsLoading &&
                !logsError &&
                !logs.length && (
                  <div className="log-empty">
                    No scans yet.
                  </div>
                )}

              {!logsLoading &&
                logs.map((log) => (
                  <div
                    className="log-row"
                    key={log.id}
                  >
                    <div
                      className={`log-dot ${log.result}`}
                    />

                    <div className="log-main">
                      <b>
                        {log.full_name ||
                          log.usn ||
                          "Unknown"}
                      </b>

                      <span>
                        {log.usn || "No USN"}
                        {log.year
                          ? ` · Year ${log.year}`
                          : ""}
                      </span>
                    </div>

                    <time>
                      {log.scanned_at
                        ? new Date(
                            log.scanned_at
                          ).toLocaleTimeString()
                        : ""}
                    </time>
                  </div>
                ))}
            </div>
          </div>
        </div>

        {result && (
          <div
            className={`scan-result ${
              result.success
                ? "success"
                : "failure"
            }`}
          >
            <div className="scan-result-top">
              <span>
                {result.success ? "✓" : "!"}
              </span>

              <div>
                <small>
                  FOODPASS VERIFICATION
                </small>

                <h3>
                  {result.success
                    ? "Verified"
                    : result.title ||
                      "Not Verified"}
                </h3>
              </div>
            </div>

            {result.full_name && (
              <div className="verified-person">
                <b>{result.full_name}</b>

                <span>
                  {result.usn || ""}
                  {result.year
                    ? ` · Year ${result.year}`
                    : ""}
                  {result.section
                    ? ` · Section ${result.section}`
                    : ""}
                  {result.food_preference
                    ? ` · ${
                        result.food_preference ===
                        "non-veg"
                          ? "Non-Veg"
                          : "Veg"
                      }`
                    : ""}
                </span>
              </div>
            )}

            {result.message && (
              <p>{result.message}</p>
            )}

            <div className="scan-result-note">
              This result will close automatically.
            </div>
          </div>
        )}
      </div>
    </Shell>
  );
}

function ScannerRoute() {
  const [staff] = useStaff();

  if (!staff?.token) {
    return <StaffLogin role="scanner" />;
  }

  return <ScannerPage />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/register" element={<Register />} />
      <Route path="/status" element={<Status />} />

      <Route
        path="/admin"
        element={<StaffLogin role="admin" />}
      />

      <Route
        path="/admin/dashboard"
        element={<Admin />}
      />

      <Route
        path="/scanner"
        element={<ScannerRoute />}
      />

      <Route path="*" element={<Home />} />
    </Routes>
  );
}