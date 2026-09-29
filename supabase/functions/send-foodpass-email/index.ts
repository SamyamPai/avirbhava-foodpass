import { createClient } from "npm:@supabase/supabase-js@2.57.0";
import QRCode from "npm:qrcode@1.5.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const EMAIL_RE = /^[a-z0-9._%+-]+@sahyadri\.edu\.in$/i;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return json(
      {
        success: false,
        message: "POST required.",
      },
      405
    );
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
    const RESEND_FROM_EMAIL = Deno.env.get("RESEND_FROM_EMAIL");

    if (
      !SUPABASE_URL ||
      !SERVICE_ROLE_KEY ||
      !RESEND_API_KEY ||
      !RESEND_FROM_EMAIL
    ) {
      return json(
        {
          success: false,
          message: "Email service is not configured.",
        },
        500
      );
    }

    const body = await req.json();

    const staffToken = String(body?.staff_token || "").trim();
    const studentId = String(body?.student_id || "").trim();

    if (!staffToken || !studentId) {
      return json(
        {
          success: false,
          message: "Staff token and student ID are required.",
        },
        400
      );
    }

    const admin = createClient(
      SUPABASE_URL,
      SERVICE_ROLE_KEY,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      }
    );

    const { data: session, error: sessionError } =
      await admin.rpc("check_staff_session", {
        p_token: staffToken,
      });

    if (
      sessionError ||
      !session?.success ||
      String(session.role || "").toLowerCase() !== "admin"
    ) {
      return json(
        {
          success: false,
          message: "Admin authorization required.",
        },
        401
      );
    }

    const { data: student, error: studentError } = await admin
      .from("students")
      .select(
        "id, full_name, email, usn, year, section, food_preference, status, redeemed, qr_token"
      )
      .eq("id", studentId)
      .maybeSingle();

    if (studentError) {
      return json(
        {
          success: false,
          message: studentError.message,
        },
        500
      );
    }

    if (!student) {
      return json(
        {
          success: false,
          message: "Student not found.",
        },
        404
      );
    }

    if (student.status !== "approved") {
      return json(
        {
          success: false,
          message:
            "Student must be approved before sending the QR.",
        },
        400
      );
    }

    if (!student.qr_token) {
      return json(
        {
          success: false,
          message:
            "This student does not have a QR token yet.",
        },
        400
      );
    }

    const email = String(student.email || "")
      .trim()
      .toLowerCase();

    if (!EMAIL_RE.test(email)) {
      return json(
        {
          success: false,
          message:
            "A valid @sahyadri.edu.in email is required.",
        },
        400
      );
    }

    const qrToken = String(student.qr_token);

    const qrDataUrl = await QRCode.toDataURL(qrToken, {
      width: 520,
      margin: 2,
      errorCorrectionLevel: "M",
    });

    const base64 = qrDataUrl.split(",")[1];

    const food =
      student.food_preference === "non-veg"
        ? "Non-Veg"
        : "Veg";

    const displayName = String(
      student.full_name || "Student"
    );

    const subject =
      "Avirbhava'26 - Food Pass Approved";

    const html = `
      <div style="font-family:Arial,sans-serif;max-width:620px;margin:0 auto;padding:24px;color:#111827">

        <h2 style="margin-bottom:6px">
          Avirbhava'26 - Food Pass Approved
        </h2>

        <p>
          Hello <strong>${escapeHtml(displayName)}</strong>,
        </p>

        <p>
          Your Food Pass registration has been approved.
        </p>

        <div style="background:#f4f7f7;border-radius:12px;padding:16px;margin:20px 0">

          <p style="margin:4px 0">
            <strong>USN:</strong>
            ${escapeHtml(student.usn || "-")}
          </p>

          <p style="margin:4px 0">
            <strong>Year:</strong>
            ${escapeHtml(String(student.year || "-"))}
          </p>

          <p style="margin:4px 0">
            <strong>Section:</strong>
            ${escapeHtml(student.section || "-")}
          </p>

          <p style="margin:4px 0">
            <strong>Food:</strong>
            ${food}
          </p>

        </div>

        <p>
          <strong>Your QR code is attached to this email.</strong>
        </p>

        <p>
          Please take a screenshot of the QR code and keep it ready for the event.
        </p>

        <p style="color:#6b7280;font-size:13px">
          CLOUDS Association presents Avirbhava'26
        </p>

      </div>
    `;

    const resendResponse = await fetch(
      "https://api.resend.com/emails",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: RESEND_FROM_EMAIL,
          to: [email],
          subject,
          html,
          attachments: [
            {
              filename: "Avirbhava26-FoodPass-QR.png",
              content: base64,
            },
          ],
        }),
      }
    );

    const resendBody = await resendResponse.json();

    if (!resendResponse.ok) {
      return json(
        {
          success: false,
          message:
            resendBody?.message ||
            "Resend could not send the email.",
        },
        502
      );
    }

    const sentAt = new Date().toISOString();

    await admin
      .from("students")
      .update({
        qr_email_sent_at: sentAt,
        updated_at: sentAt,
      })
      .eq("id", student.id);

    return json({
      success: true,
      message: "QR email sent.",
      sent_at: sentAt,
      email,
    });
  } catch (error) {
    return json(
      {
        success: false,
        message:
          error instanceof Error
            ? error.message
            : "Unexpected email error.",
      },
      500
    );
  }
});

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}