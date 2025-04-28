from typing import List


class ValidatorException(Exception):
    def __init__(self, errors: List[str]):
        self.errors = errors
        super().__init__(self.errors)


class Validator:

    def __init__(self, object_input):
        self.object_input = object_input
        self.error_messages: List[str] = []

    def validate(self, projection, predicate, error_message):
        predicate_on_field = predicate(projection(self.object_input))

        if not predicate_on_field:
            self.error_messages.append(error_message)

        return self

    def get_error_message(self):
        return self.error_messages

    def get_or_else_throw(self):
        if self.error_messages:
            raise ValidatorException(self.error_messages)
