async function fetchNotes() {
  const res = await fetch("/api/notes");
  if (res.status === 401) return (window.location.href = "login.html");
  const notes = await res.json();
  const notesList = document.getElementById("notes-list");
  notesList.innerHTML = "";
  notes.forEach(note => {
    const div = document.createElement("div");
    div.className = "note";
    div.innerHTML = `<h3 contenteditable="true" oninput="editNote(${note.id}, this, 'title')">${note.title}</h3>
    <p contenteditable="true" oninput="editNote(${note.id}, this, 'content')">${note.content}</p>
    <button onclick="deleteNote(${note.id})">Delete</button>`;
    notesList.appendChild(div);
  });
}

document.getElementById("note-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const title = document.getElementById("title").value;
  const content = document.getElementById("content").value;
  await fetch("/api/notes", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title, content })
  });
  document.getElementById("title").value = "";
  document.getElementById("content").value = "";
  fetchNotes();
});

async function deleteNote(id) {
  await fetch(`/api/notes/${id}`, { method: "DELETE" });
  fetchNotes();
}

let editTimer;
function editNote(id, element, field) {
  clearTimeout(editTimer);
  editTimer = setTimeout(async () => {
    const value = element.innerText;
    await fetch(`/api/notes/${id}`, {
      method: "PUT", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ [field]: value })
    });
  }, 500);
}

function logout() {
  fetch("/api/auth/logout", { method: "POST" }).then(() => {
    location.href = "login.html";
  });
}

fetchNotes();