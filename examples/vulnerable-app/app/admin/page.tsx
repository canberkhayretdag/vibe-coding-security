"use client";
import { useEffect, useState } from "react";

export default function AdminPage() {
  const [users, setUsers] = useState([]);
  const isAdmin = typeof window !== "undefined" && localStorage.getItem("role") === "admin";

  useEffect(() => {
    fetch("/api/admin/users").then((r) => r.json()).then(setUsers);
  }, []);

  if (!isAdmin) return <p>Not allowed</p>;
  return <pre>{JSON.stringify(users, null, 2)}</pre>;
}
