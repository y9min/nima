(function () {
  function normalizeEmail(value) {
    return String(value || "").trim().toLowerCase();
  }

  function isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }

  function setStatus(element, message, kind) {
    if (!element) return;
    element.textContent = message;
    element.dataset.status = kind;
  }

  window.NimaAndroidWaitlist = {
    init: function (options) {
      var form = document.querySelector(options.form);
      var emailInput = document.querySelector(options.email);
      var status = options.status ? document.querySelector(options.status) : null;
      var supabaseUrl = options.supabaseUrl;
      var supabaseAnonKey = options.supabaseAnonKey;

      if (!form || !emailInput || !supabaseUrl || !supabaseAnonKey) {
        throw new Error("Missing Android waitlist configuration.");
      }

      form.dataset.waitlistReady = "true";
      form.addEventListener("submit", async function (event) {
        event.preventDefault();

        var email = normalizeEmail(emailInput.value);
        if (!isValidEmail(email)) {
          setStatus(status, "Enter a valid email.", "error");
          return;
        }

        setStatus(status, "Joining waitlist...", "loading");

        try {
          var response = await fetch(
            supabaseUrl.replace(/\/$/, "") + "/rest/v1/android_waitlist",
            {
              method: "POST",
              headers: {
                apikey: supabaseAnonKey,
                Authorization: "Bearer " + supabaseAnonKey,
                "Content-Type": "application/json",
                Prefer: "return=minimal",
              },
              body: JSON.stringify({ email: email }),
            }
          );

          if (!response.ok) {
            var errorBody = await response.json().catch(function () {
              return null;
            });
            if (errorBody && errorBody.code === "23505") {
              emailInput.value = email;
              setStatus(status, "You're already on the Android waitlist.", "success");
              return;
            }
            throw new Error("Waitlist request failed.");
          }

          emailInput.value = email;
          setStatus(status, "You're on the Android waitlist.", "success");
        } catch (error) {
          setStatus(status, "Could not join right now. Try again soon.", "error");
        }
      });
    },
  };
})();
