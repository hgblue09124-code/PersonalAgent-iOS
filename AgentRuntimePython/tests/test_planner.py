import unittest

from personal_agent_runtime import IntentKind, PlanKind, plan_request


class PlannerTests(unittest.TestCase):
    def test_blank_request_asks_for_clarification(self):
        plan = plan_request("  \n ")
        self.assertEqual(plan.kind, PlanKind.CLARIFY)
        self.assertIn("request", plan.missing_fields)
        self.assertFalse(plan.is_executable)

    def test_bare_create_file_asks_for_missing_details(self):
        for prompt in ("Tạo file", "tao mot file", "Create file"):
            with self.subTest(prompt=prompt):
                plan = plan_request(prompt, allowed_skill_ids={"workspace.create-file"})
                self.assertEqual(plan.intent.kind, IntentKind.CREATE_FILE)
                self.assertEqual(plan.kind, PlanKind.CLARIFY)
                self.assertIn("path", plan.missing_fields)
                self.assertIn("content", plan.missing_fields)
                self.assertIsNone(plan.skill_id)
                self.assertFalse(plan.is_executable)

    def test_complete_request_only_proposes_when_skill_is_in_scope(self):
        prompt = "Tạo file workspace/hello.txt nội dung: xin chao"
        plan = plan_request(prompt, allowed_skill_ids={"workspace.create-file"})
        self.assertEqual(plan.kind, PlanKind.PROPOSE_SKILL)
        self.assertEqual(plan.skill_id, "workspace.create-file")
        self.assertEqual(plan.arguments, {"path": "workspace/hello.txt", "content": "xin chao"})
        self.assertFalse(plan.is_executable)
        self.assertFalse(plan.to_dict()["is_executable"])

    def test_complete_request_without_capability_fails_closed(self):
        plan = plan_request("Create file workspace/hello.txt content: hello", allowed_skill_ids=())
        self.assertEqual(plan.kind, PlanKind.UNSUPPORTED)
        self.assertIsNone(plan.skill_id)
        self.assertEqual(plan.arguments, {})
        self.assertFalse(plan.is_executable)

    def test_generic_chat_never_proposes_a_skill(self):
        plan = plan_request("Giải thích quy luật tích lũy tài sản")
        self.assertEqual(plan.kind, PlanKind.RESPOND)
        self.assertEqual(plan.intent.kind, IntentKind.CHAT)
        self.assertIsNone(plan.skill_id)
        self.assertFalse(plan.is_executable)


if __name__ == "__main__":
    unittest.main()
