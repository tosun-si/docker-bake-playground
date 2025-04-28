from typing import List

import pytest

from common_lib.validator import Validator, ValidatorException

FIRST_NAME_ERROR_MESSAGE = 'First name should not be empty.'
LAST_NAME_ERROR_MESSAGE = 'Last name should not be empty.'


class TestValidator:
    """
    All tests for validator file
    """

    def test_given_object_without_error_fields_when_validate_it_then_no_error_in_result(self):
        person = {
            'first_name': 'Kylian',
            'last_name': 'Mbappe'
        }

        # When.
        result_error_messages: List[str] = (
            Validator(person)
                .validate(lambda p: p['first_name'], lambda f_name: f_name != '', FIRST_NAME_ERROR_MESSAGE)
                .validate(lambda p: p['last_name'], lambda l_name: l_name != '', LAST_NAME_ERROR_MESSAGE)
                .get_error_message()
        )

        # Then.
        assert result_error_messages == []

    @pytest.mark.parametrize(
        "input_first_name,input_last_name,expected_error_messages",
        [
            ('Kylian', '', [LAST_NAME_ERROR_MESSAGE]),
            ('', 'Mbappe', [FIRST_NAME_ERROR_MESSAGE]),
            ('', '', [FIRST_NAME_ERROR_MESSAGE, LAST_NAME_ERROR_MESSAGE])
        ]
    )
    def test_given_object_with_error_fields_when_validate_it_then_expected_error_messages_in_result(
            self,
            input_first_name: str,
            input_last_name: str,
            expected_error_messages: List[str]):
        person = {
            'first_name': input_first_name,
            'last_name': input_last_name
        }

        # When.
        result_error_messages: List[str] = (
            Validator(person)
                .validate(lambda p: p['first_name'], lambda f_name: f_name != '', FIRST_NAME_ERROR_MESSAGE)
                .validate(lambda p: p['last_name'], lambda l_name: l_name != '', LAST_NAME_ERROR_MESSAGE)
                .get_error_message()
        )

        # Then.
        assert all(elem in result_error_messages for elem in expected_error_messages)

    @pytest.mark.parametrize(
        "input_first_name,input_last_name,expected_error_messages",
        [
            ('Kylian', '', [LAST_NAME_ERROR_MESSAGE]),
            ('', 'Mbappe', [FIRST_NAME_ERROR_MESSAGE]),
            ('', '', [FIRST_NAME_ERROR_MESSAGE, LAST_NAME_ERROR_MESSAGE])
        ]
    )
    def test_given_object_with_error_fields_when_validate_it_with_get_or_else_throw_then_raise_validator_exception_with_expected_error_messages(
            self,
            input_first_name: str,
            input_last_name: str,
            expected_error_messages: List[str]):
        person = {
            'first_name': input_first_name,
            'last_name': input_last_name
        }

        # When.
        with pytest.raises(ValidatorException) as excinfo:
            (Validator(person)
             .validate(lambda p: p['first_name'], lambda f_name: f_name != '', FIRST_NAME_ERROR_MESSAGE)
             .validate(lambda p: p['last_name'], lambda l_name: l_name != '', LAST_NAME_ERROR_MESSAGE)
             .get_or_else_throw())

        # Then.
        for error_message in expected_error_messages:
            assert error_message in str(excinfo.value)
