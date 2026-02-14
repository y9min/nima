import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { createClient } from "@supabase/supabase-js";

export function registerTools(server: McpServer) {
  server.registerTool(
    "ping",
    { description: "Returns pong — proves the MCP server is alive" },
    async () => ({
      content: [{ type: "text" as const, text: "pong" }],
    })
  );

  server.registerTool(
    "whoami",
    {
      description: "Returns the current user's profile from Supabase",
      inputSchema: {
        userId: z
          .string()
          .optional()
          .describe("User ID to look up. Falls back to BUBBLE_USER_ID env var."),
      },
    },
    async ({ userId }) => {
      const id = userId || process.env.BUBBLE_USER_ID;
      if (!id) {
        return {
          content: [{ type: "text" as const, text: "No user ID provided. Set BUBBLE_USER_ID or pass userId." }],
          isError: true,
        };
      }

      const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
      if (!url || !key) {
        return {
          content: [{ type: "text" as const, text: "Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY." }],
          isError: true,
        };
      }

      const supabase = createClient(url, key);
      const { data, error } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", id)
        .single();

      if (error) {
        return {
          content: [{ type: "text" as const, text: `Error: ${error.message}` }],
          isError: true,
        };
      }

      return {
        content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
